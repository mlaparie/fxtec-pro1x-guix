#!/usr/bin/env bash
# scripts/flash.sh — flash U-Boot and a Guix system onto the F(x)tec Pro1X
#
# Run with --help for usage.

set -euo pipefail

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
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found — run: guix shell fastboot mkbootimg -- bash $0"; }
ask()  { local yn; read -r -p "$1 [Y/n] " yn; [[ "${yn:-Y}" =~ ^[Yy]$ ]]; }
# Run a command, suppressing stderr unless --verbose was passed.
quiet() { if [[ "$VERBOSE" == true ]]; then "$@"; else "$@" 2>/dev/null; fi; }

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
Usage: sudo bash scripts/flash.sh [OPTIONS]

Flash U-Boot and a Guix root filesystem onto the F(x)tec Pro1X via fastboot.
The device must be in fastboot mode (hold Vol-Down at power-on).
Run as root (sudo) unless you have a udev rule granting your user fastboot access.

Options:
  --uboot FILE     Path to u-boot-nodtb.bin
  --dtb FILE       Path to sm6115-fxtec-pro1x.dtb (default: same dir as --uboot)
  --rootfs FILE    Path to rootfs.img (pre-extracted ext4 partition)
  --system FILE    Guix system .scm to build if rootfs is not found
                   (default: systems/mobile.scm)
  -v, --verbose    Show all dd progress and suppress no stderr output
  -h, --help       Show this help

Artifact discovery order (tried in sequence for both U-Boot and rootfs):
  1. Explicit flag (--uboot / --rootfs)
  2. Local files in the current directory:
       u-boot-nodtb.bin + sm6115-fxtec-pro1x.dtb   (as downloaded from GitHub releases)
       rootfs.img
  3. Guix store (/gnu/store) — offered interactively if Guix is installed
  4. Build with Guix  — offered interactively (U-Boot: ~2 h; rootfs: ~30 min)

Examples:
  # Use pre-downloaded GitHub release artifacts in the current directory:
  sudo bash scripts/flash.sh

  # Explicit paths:
  sudo bash scripts/flash.sh --uboot ~/Downloads/u-boot.bin --rootfs ~/Downloads/rootfs.img

  # Force a fresh build of a specific system:
  sudo guix shell fastboot mkbootimg -- bash scripts/flash.sh --system systems/minimal.scm
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

need fastboot
need mkbootimg

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Find U-Boot ───────────────────────────────────────────────────────────────
echo "==> Finding U-Boot …"
UBOOT_BIN=""
UBOOT_DTB=""

if [[ -n "$OPT_UBOOT" ]]; then
    UBOOT_BIN="$OPT_UBOOT"
    UBOOT_DTB="${OPT_DTB:-$(dirname "$OPT_UBOOT")/sm6115-fxtec-pro1x.dtb}"
    echo "    Using: $UBOOT_BIN"
elif [[ -f "u-boot-nodtb.bin" && -f "sm6115-fxtec-pro1x.dtb" ]]; then
    UBOOT_BIN="u-boot-nodtb.bin"
    UBOOT_DTB="sm6115-fxtec-pro1x.dtb"
    echo "    Found local files."
elif command -v guix >/dev/null 2>&1; then
    # guix build returns the store path instantly if already built, or builds it.
    ask "    Not found locally. Use Guix to find/build u-boot-pro1x?" || die "Aborted."
    BUILT=$(guix_build_path guix build u-boot-pro1x -L . --fallback)
    [[ -d "$BUILT" ]] || die "U-Boot build failed"
    UBOOT_BIN="$BUILT/libexec/u-boot-nodtb.bin"
    UBOOT_DTB="$BUILT/libexec/sm6115-fxtec-pro1x.dtb"
else
    die "u-boot-nodtb.bin not found and Guix is not installed.
Download u-boot-nodtb.bin + sm6115-fxtec-pro1x.dtb from the GitHub releases page
and place them in the current directory, or pass --uboot / --dtb."
fi

[[ -f "$UBOOT_BIN" ]]  || die "u-boot-nodtb.bin not found at: $UBOOT_BIN"
[[ -f "$UBOOT_DTB" ]]  || die "DTB not found at: $UBOOT_DTB"
echo "    u-boot-nodtb.bin: $UBOOT_BIN"
echo "    DTB:        $UBOOT_DTB"

# ── Find rootfs ───────────────────────────────────────────────────────────────
echo "==> Finding rootfs …"
ROOTFS_FLASH=""   # final path passed to fastboot
NEED_EXTRACT=false
DISK_IMAGE=""

if [[ -n "$OPT_ROOTFS" ]]; then
    ROOTFS_FLASH="$OPT_ROOTFS"
    echo "    Using: $ROOTFS_FLASH"
elif [[ -f "rootfs.img" ]]; then
    ROOTFS_FLASH="rootfs.img"
    echo "    Found local file: rootfs.img"
elif command -v guix >/dev/null 2>&1; then
    ask "    Not found locally. Use Guix to find/build system image?" || die "Aborted."
    DISK_IMAGE=$(guix_build_path guix system image --image-type=efi-raw --system="$ARCH" -L . "$SYSTEM")
    [[ -f "$DISK_IMAGE" ]] || die "System image build failed"
    NEED_EXTRACT=true
else
    die "rootfs.img not found and Guix is not installed.
Download rootfs.img from the GitHub releases page and place it in the
current directory, or pass --rootfs."
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
