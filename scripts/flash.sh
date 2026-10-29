#!/usr/bin/env bash
# scripts/flash.sh — flash U-Boot and a Guix system onto the F(x)tec Pro1X
#
# Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/../manifest.scm"

ARCH="aarch64-linux"
SYSTEM="systems/mobile.scm"
OPT_UBOOT=""
OPT_DTB=""
OPT_ROOTFS=""
VERBOSE=false

# ── Boot image parameters (Qualcomm SM6115) ──────────────────────────────────
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100

die()  { echo "error: $*" >&2; exit 1; }
ask()  { local yn; read -r -p "$1 [Y/n] " yn; [[ "${yn:-Y}" =~ ^[Yy]$ ]]; }
# Run a command, suppressing stderr unless --verbose was passed.
quiet() { if [[ "$VERBOSE" == true ]]; then "$@"; else "$@" 2>/dev/null; fi; }

# Query the guix store DB for when a path was built/substituted.
store_date() {
    python3 - "$1" 2>/dev/null <<'PYEOF'
import sys, sqlite3, datetime
try:
    con = sqlite3.connect('file:/var/guix/db/db.sqlite?mode=ro&immutable=1', uri=True, timeout=2)
    row = con.execute('SELECT registrationTime FROM ValidPaths WHERE path=?',
                      (sys.argv[1],)).fetchone()
    if row:
        print(datetime.datetime.fromtimestamp(row[0]).strftime('%Y-%m-%d %H:%M'))
except Exception:
    pass
PYEOF
}

# Find cached store outputs for CMD ARGS; let user pick one or build new.
# Interactive prompts/listing → stderr. Chosen store path → stdout.
guix_select_or_build() {
    local label="$1"; shift
    local hits=()
    # Phase 1: --dry-run — works for "guix build" (prints output paths when cached).
    local _dry; _dry=$(mktemp)
    { "$@" --dry-run 2>&1 || true; } > "$_dry"
    while IFS= read -r p; do
        [[ -e "$p" ]] && hits+=("$p")
    done < <(grep '^/gnu/store' "$_dry" | grep -v '\.drv$')
    rm -f "$_dry"

    # Phase 2: quick probe — "guix system image --dry-run" silently ignores --dry-run
    # and outputs nothing.  Run without it; if the image is cached the command returns
    # the store path in ~7 s (daemon round-trip).  timeout kills the client if a real
    # build would be needed; daemon state is unaffected by client disconnect.
    if [[ ${#hits[@]} -eq 0 ]]; then
        local _quick
        _quick=$(timeout 15 "$@" 2>/dev/null | grep '^/gnu/store' | grep -v '\.drv$' | tail -1)
        [[ -e "$_quick" ]] && hits+=("$_quick")
    fi

    local choice=""
    if [[ ${#hits[@]} -gt 0 ]]; then
        for i in "${!hits[@]}"; do
            local ts; ts=$(store_date "${hits[$i]}")
            printf "    %d) cached  %s  [%s]\n" "$((i+1))" "${hits[$i]}" "${ts:-unknown}" >&2
        done
        printf "    %d) build new\n" "$((${#hits[@]}+1))" >&2
        local _pick
        read -r -p "    select [1]: " _pick
        _pick="${_pick:-1}"
        if [[ "$_pick" =~ ^[0-9]+$ && "$_pick" -ge 1 && "$_pick" -le "${#hits[@]}" ]]; then
            choice="${hits[$((_pick-1))]}"
        fi
        # selecting "build new" or out-of-range leaves choice empty → falls through to build
    fi

    if [[ -z "$choice" ]]; then
        if [[ ${#hits[@]} -gt 0 ]]; then
            printf "    building %s (guix is deterministic — same image if config unchanged) …\n" \
                "$label" >&2
        else
            ask "    build $label?" || die "Aborted."
        fi
        choice=$(guix_build_path "$@" --fallback)
        [[ -n "$choice" ]] || die "$label build failed"
        local _cached_hit
        for _cached_hit in "${hits[@]}"; do
            if [[ "$choice" == "$_cached_hit" ]]; then
                printf "    (config unchanged — same image as cached)\n" >&2
                break
            fi
        done
    fi
    echo "$choice"
}

# Run CMD, stream output live to stderr, return the last /gnu/store path found.
# Avoids the pipe-buffering that silences guix progress when capturing via $().
# With --verbose, injects --verbosity=3 after 'guix' to stream compile logs.
guix_build_path() {
    local log; log=$(mktemp)
    local cmd=("$@")
    [[ "$VERBOSE" == true ]] && cmd=("${cmd[0]}" "--verbosity=3" "${cmd[@]:1}")
    "${cmd[@]}" 2>&1 | tee /dev/stderr > "$log"
    grep '^/gnu/store' "$log" | grep -v '\.drv' | tail -1
    rm -f "$log"
}

show_help() {
    cat <<EOF
Usage: bash scripts/flash.sh [OPTIONS]

Flash U-Boot and a Guix root filesystem onto the F(x)tec Pro1X via fastboot.
The device must be in fastboot mode (hold Vol-Down at power-on).
fastboot commands are run via sudo internally (USB device access).

Options:
  --uboot FILE     Path to u-boot-nodtb.bin
  --dtb FILE       Path to sm6115-fxtec-pro1x.dtb (default: same dir as --uboot)
  --rootfs FILE    Path to rootfs.img (pre-extracted ext4 partition)
  --system FILE    Guix system .scm (prompted interactively if omitted)
  -v, --verbose    Show all dd progress and suppress no stderr output
  -h, --help       Show this help

Systems in systems/:
  mobile.scm           Phosh desktop, unencrypted userdata  [default]
  minimal.scm          Headless, SSH only (fast build, good for testing)
  mobile-encrypted.scm Phosh desktop, LUKS2 full-disk encryption
                       (delegates to flash-encrypted.sh automatically)

Artifact discovery (tried in order for both U-Boot and rootfs):
  1. Explicit flag (--uboot / --rootfs)
  2. Local files: u-boot-nodtb.bin + sm6115-fxtec-pro1x.dtb, rootfs.img
  3. Guix store — checked via "guix build --dry-run"; prints path + date if cached
  4. Guix build — offered interactively if not cached (U-Boot: ~2 h; rootfs: ~30 min)

If guix is in PATH, the script re-execs itself inside "guix shell -m manifest.scm"
for a reproducible tooling environment (fastboot, mkbootimg, partx, e2label).
Without guix, those tools must already be installed.

Examples:
  bash scripts/flash.sh
  bash scripts/flash.sh --uboot ~/Downloads/u-boot.bin --rootfs ~/Downloads/rootfs.img
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uboot)        OPT_UBOOT="$2";  shift 2 ;;
        --dtb)          OPT_DTB="$2";    shift 2 ;;
        --rootfs)       OPT_ROOTFS="$2"; shift 2 ;;
        --system)       SYSTEM="$2";     shift 2 ;;
        -v|--verbose)   VERBOSE=true;    shift ;;
        -h|--help)      show_help; exit 0 ;;
        *.scm)          SYSTEM="$1"; shift ;;
        *) die "Unknown argument: $1  (try --help)" ;;
    esac
done

# ── Tool environment ──────────────────────────────────────────────────────────
# Re-exec inside guix shell for a reproducible tooling environment.
# If guix is not available, fall through and check each tool manually.
if [[ -z "${_IN_GUIX_SHELL:-}" ]] && command -v guix >/dev/null 2>&1; then
    [[ -f "$MANIFEST" ]] || die "manifest.scm not found at $MANIFEST"
    export _IN_GUIX_SHELL=1
    exec guix shell -m "$MANIFEST" -- bash "$0" "$@"
fi
for _t in fastboot mkbootimg partx e2label python3; do
    command -v "$_t" >/dev/null 2>&1 \
        || die "$_t not found (Guix unavailable; install fastboot mkbootimg util-linux e2fsprogs python3)"
done

# fastboot needs USB device access — wrap with sudo.
# Capture the real path now so sudo gets the store path, not a shell function.
export _FASTBOOT_BIN="$(command -v fastboot)"
fastboot() { sudo "$_FASTBOOT_BIN" "$@"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Select system (when we'll need to build one) ──────────────────────────────
# Prompt only if no --system flag, no --rootfs flag, and no local rootfs.img.
if [[ -z "$OPT_ROOTFS" && ! -f "rootfs.img" && "$SYSTEM" == "systems/mobile.scm" ]]; then
    mapfile -t SCMS < <(ls systems/*.scm 2>/dev/null | sort)
    if [[ ${#SCMS[@]} -gt 1 ]]; then
        echo "Available systems:"
        for i in "${!SCMS[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${SCMS[$i]}"
        done
        # Default to mobile.scm if present, else item 1
        default_idx=1
        for i in "${!SCMS[@]}"; do
            [[ "${SCMS[$i]}" == "systems/mobile.scm" ]] && default_idx=$((i+1)) && break
        done
        read -r -p "Select [$default_idx]: " _pick
        _pick="${_pick:-$default_idx}"
        [[ "$_pick" =~ ^[0-9]+$ && "$_pick" -ge 1 && "$_pick" -le "${#SCMS[@]}" ]] \
            || die "invalid selection"
        SYSTEM="${SCMS[$((_pick-1))]}"
    fi
fi
echo "System: $SYSTEM"
echo ""

# ── Find U-Boot ───────────────────────────────────────────────────────────────
echo "==> U-Boot"
UBOOT_BIN=""
UBOOT_DTB=""

if [[ -n "$OPT_UBOOT" ]]; then
    UBOOT_BIN="$OPT_UBOOT"
    UBOOT_DTB="${OPT_DTB:-$(dirname "$OPT_UBOOT")/sm6115-fxtec-pro1x.dtb}"
elif [[ -f "u-boot-nodtb.bin" && -f "sm6115-fxtec-pro1x.dtb" ]]; then
    UBOOT_BIN="u-boot-nodtb.bin"
    UBOOT_DTB="sm6115-fxtec-pro1x.dtb"
    echo "    local files"
elif command -v guix >/dev/null 2>&1; then
    BUILT=$(guix_select_or_build "u-boot-pro1x" guix build u-boot-pro1x -L .)
    [[ -d "$BUILT" ]] || die "U-Boot not found: $BUILT"
    UBOOT_BIN="$BUILT/libexec/u-boot-nodtb.bin"
    UBOOT_DTB="$BUILT/libexec/sm6115-fxtec-pro1x.dtb"
else
    die "u-boot-nodtb.bin not found and Guix is not installed — pass --uboot or install Guix"
fi

[[ -f "$UBOOT_BIN" ]] || die "not found: $UBOOT_BIN"
[[ -f "$UBOOT_DTB" ]] || die "not found: $UBOOT_DTB"

# Encrypted path: find the disk image here, export everything, delegate assembly.
if [[ "$SYSTEM" == "systems/mobile-encrypted.scm" ]]; then
    echo "==> System image ($SYSTEM)"
    DISK_IMAGE=$(guix_select_or_build "system image" \
        guix system image --image-type=efi-raw --system="$ARCH" -L modules "$SYSTEM")
    [[ -f "$DISK_IMAGE" ]] || die "System image not found: $DISK_IMAGE"
    export _UBOOT_BIN="$UBOOT_BIN" _UBOOT_DTB="$UBOOT_DTB" _DISK_IMAGE="$DISK_IMAGE"
    exec bash "$SCRIPT_DIR/flash-encrypted.sh"
fi

# ── Find rootfs ───────────────────────────────────────────────────────────────
echo "==> Rootfs"
ROOTFS_FLASH=""   # final path passed to fastboot
NEED_EXTRACT=false
DISK_IMAGE=""

if [[ -n "$OPT_ROOTFS" ]]; then
    ROOTFS_FLASH="$OPT_ROOTFS"
elif [[ -f "rootfs.img" ]]; then
    ROOTFS_FLASH="rootfs.img"
    echo "    local file: rootfs.img"
elif command -v guix >/dev/null 2>&1; then
    DISK_IMAGE=$(guix_select_or_build "system image" \
        guix system image --image-type=efi-raw --system="$ARCH" -L modules "$SYSTEM")
    [[ -f "$DISK_IMAGE" ]] || die "System image not found: $DISK_IMAGE"
    NEED_EXTRACT=true
else
    die "rootfs.img not found and Guix is not installed — pass --rootfs or install Guix"
fi

# ── Prepare artifacts ─────────────────────────────────────────────────────────
echo "==> Wrapping U-Boot as boot.img …"
# U-Boot's ARM64 Image header has text_offset = -0x80000000 (bytes 8-15).
# The Qualcomm ABL rejects that and falls straight back to fastboot.
# Zero the field so ABL sees offset=0 (same as Linux) and accepts the image.
# Gzip-compress and append the DTB so ABL extracts it and passes it in x0.
cp "$UBOOT_BIN" "$TMPDIR/u-boot.bin"
chmod +w "$TMPDIR/u-boot.bin"
printf '\x00\x00\x00\x00\x00\x00\x00\x00' \
    | quiet dd of="$TMPDIR/u-boot.bin" bs=1 seek=8 count=8 conv=notrunc
gzip --no-name -9 -c "$TMPDIR/u-boot.bin" > "$TMPDIR/u-boot.bin.gz"
cat "$TMPDIR/u-boot.bin.gz" "$UBOOT_DTB" > "$TMPDIR/u-boot.bin.gz-dtb"
mkbootimg \
    --kernel  "$TMPDIR/u-boot.bin.gz-dtb" \
    --pagesize  $PAGESIZE \
    --base      $BASE \
    --kernel_offset  $KERNEL_OFFSET \
    --ramdisk_offset $RAMDISK_OFFSET \
    --tags_offset    $TAGS_OFFSET \
    --output "$TMPDIR/boot.img"

if [[ "$NEED_EXTRACT" == true ]]; then
    echo "==> Extracting root partition from disk image …"
    PART_INFO=$(partx -o START,SECTORS -g -n 2 "$DISK_IMAGE")
    PART_START=$(echo "$PART_INFO" | awk '{print $1}')
    PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
    [[ -n "$PART_START" && -n "$PART_SECTORS" ]] \
        || die "Could not read partition table from disk image"
    DD_PROGRESS=(); [[ "$VERBOSE" == true ]] && DD_PROGRESS=(status=progress)
    dd if="$DISK_IMAGE" of="$TMPDIR/rootfs.img" \
        bs=512 skip="$PART_START" count="$PART_SECTORS" "${DD_PROGRESS[@]}"
    ROOTFS_FLASH="$TMPDIR/rootfs.img"
    ROOTFS_MIB=$(( PART_SECTORS / 2048 ))
else
    ROOTFS_MIB=$(( $(wc -c < "$ROOTFS_FLASH") / 1024 / 1024 ))
fi

ACTUAL_LABEL=$(quiet e2label "$ROOTFS_FLASH" || true)
if [[ "$ACTUAL_LABEL" != "guix" ]]; then
    echo "    Relabelling root partition 'guix' (was: '${ACTUAL_LABEL:-<none>}') …"
    e2label "$ROOTFS_FLASH" guix
fi

echo "==> Generating vbmeta with verification disabled …"
# Proper AvbVBMetaImageHeader (256 bytes, big-endian) padded to 4096 bytes.
# flags=2 (VERIFICATION_DISABLED) matches the NixOS port; no keys, algorithm NONE.
python3 -c "
import struct, sys
HEADER = (
    '>4s'   # magic
    'II'    # required libavb version major, minor
    'Q'     # authentication data block size
    'Q'     # auxiliary data block size
    'I'     # algorithm type (0 = NONE)
    'QQ'    # hash offset, size
    'QQ'    # signature offset, size
    'QQ'    # public key offset, size
    'QQ'    # public key metadata offset, size
    'QQ'    # descriptors offset, size
    'Q'     # rollback index
    'I'     # flags
    'I'     # rollback index location
    '48s'   # release string
    '80x'   # reserved
)
hdr = struct.pack(HEADER,
    b'AVB0', 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    2,  # VERIFICATION_DISABLED
    0, b'pro1x-guix'.ljust(48, b'\x00'))
sys.stdout.buffer.write(hdr.ljust(4096, b'\x00'))
" > "$TMPDIR/vbmeta.img"

# ── Verify ────────────────────────────────────────────────────────────────────
BOOT_SIZE=$(wc -c < "$TMPDIR/boot.img")
[[ "$BOOT_SIZE"  -gt 0 ]] || die "boot.img is empty"
[[ "$ROOTFS_MIB" -gt 0 ]] || die "rootfs is empty"

echo ""
echo "==> All artifacts ready — device must be in fastboot mode before continuing."
echo "    boot.img : $TMPDIR/boot.img  ($(( BOOT_SIZE / 1024 )) KiB)"
echo "    rootfs   : $ROOTFS_FLASH  ($ROOTFS_MIB MiB)"
echo "    vbmeta   : $TMPDIR/vbmeta.img"
echo ""
echo "    Flashing will erase userdata and replace the bootloader on slot A."
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
CONFIRM="${CONFIRM//$'\r'/}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Flash ─────────────────────────────────────────────────────────────────────
echo "==> Erasing dtbo …"
fastboot erase dtbo

echo "==> Flashing U-Boot to both slots (prevents A/B bootloop) …"
fastboot flash boot_a "$TMPDIR/boot.img"
fastboot flash boot_b "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification on both slots …"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"
fastboot flash vbmeta_b "$TMPDIR/vbmeta.img"

echo "==> Flashing rootfs to userdata …"
fastboot flash userdata "$ROOTFS_FLASH"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done.  First boot initialises the Guix store (~2 min)."
echo "SSH: ssh user@172.16.42.1  (password: 123456 — change it!)"
