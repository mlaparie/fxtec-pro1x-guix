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

show_help() {
    cat <<EOF
Usage: bash scripts/flash.sh [OPTIONS]

Flash U-Boot and a Guix root filesystem onto the F(x)tec Pro1X via fastboot.
The device must be in fastboot mode (hold Vol-Down at power-on).

Options:
  --uboot FILE     Path to u-boot.bin
  --dtb FILE       Path to sm6115-fxtec-pro1x.dtb (default: same dir as --uboot)
  --rootfs FILE    Path to rootfs.img (pre-extracted ext4 partition)
  --system FILE    Guix system .scm to build if rootfs is not found
                   (default: systems/mobile.scm)
  -h, --help       Show this help

Artifact discovery order (tried in sequence for both U-Boot and rootfs):
  1. Explicit flag (--uboot / --rootfs)
  2. Local files in the current directory:
       u-boot.bin + sm6115-fxtec-pro1x.dtb   (as downloaded from GitHub releases)
       rootfs.img
  3. Guix store (/gnu/store) — offered interactively if Guix is installed
  4. Build with Guix  — offered interactively (U-Boot: ~2 h; rootfs: ~30 min)

Examples:
  # Use pre-downloaded GitHub release artifacts in the current directory:
  bash scripts/flash.sh

  # Explicit paths:
  bash scripts/flash.sh --uboot ~/Downloads/u-boot.bin --rootfs ~/Downloads/rootfs.img

  # Force a fresh build of a specific system:
  bash scripts/flash.sh --system systems/minimal.scm
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uboot)   OPT_UBOOT="$2";  shift 2 ;;
        --dtb)     OPT_DTB="$2";    shift 2 ;;
        --rootfs)  OPT_ROOTFS="$2"; shift 2 ;;
        --system)  SYSTEM="$2";     shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *.scm)     SYSTEM="$1"; shift ;;
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
elif [[ -f "u-boot.bin" && -f "sm6115-fxtec-pro1x.dtb" ]]; then
    UBOOT_BIN="u-boot.bin"
    UBOOT_DTB="sm6115-fxtec-pro1x.dtb"
    echo "    Found local files."
elif command -v guix >/dev/null 2>&1; then
    STORE_UBOOT=$(find /gnu/store -maxdepth 1 -name "*-u-boot-pro1x-*" \
        ! -name "*.drv" ! -name "*-checkout" ! -name "*-builder" ! -name "*lock*" \
        2>/dev/null | sort | tail -1)
    if [[ -d "${STORE_UBOOT:-}" ]]; then
        echo "    Found in Guix store: $STORE_UBOOT"
        ask "    Use it?" || die "Aborted."
        UBOOT_BIN="$STORE_UBOOT/libexec/u-boot.bin"
        UBOOT_DTB="$STORE_UBOOT/libexec/sm6115-fxtec-pro1x.dtb"
    else
        echo "    Not found locally or in store."
        ask "    Build with Guix? (requires cross-compiler, ~2 h)" || die "Aborted."
        BUILT=$(guix time-machine --disable-authentication -C channels-ci.scm -- \
            build u-boot-pro1x -L . --no-grafts 2>&1 | tee /dev/stderr | tail -1)
        [[ -d "$BUILT" ]] || die "U-Boot build failed"
        UBOOT_BIN="$BUILT/libexec/u-boot.bin"
        UBOOT_DTB="$BUILT/libexec/sm6115-fxtec-pro1x.dtb"
    fi
else
    die "u-boot.bin not found and Guix is not installed.
Download u-boot.bin + sm6115-fxtec-pro1x.dtb from the GitHub releases page
and place them in the current directory, or pass --uboot / --dtb."
fi

[[ -f "$UBOOT_BIN" ]]  || die "u-boot.bin not found at: $UBOOT_BIN"
[[ -f "$UBOOT_DTB" ]]  || die "DTB not found at: $UBOOT_DTB"
echo "    u-boot.bin: $UBOOT_BIN"
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
    STORE_DISK=$(find /gnu/store -maxdepth 1 -name "*-disk-image" \
        ! -name "*.drv" 2>/dev/null | sort | tail -1)
    if [[ -f "${STORE_DISK:-}" ]]; then
        echo "    Found disk image in Guix store: $STORE_DISK"
        ask "    Use it?" || die "Aborted."
        DISK_IMAGE="$STORE_DISK"
        NEED_EXTRACT=true
    else
        echo "    Not found locally or in store."
        ask "    Build with Guix? (~30 min)" || die "Aborted."
        DISK_IMAGE=$(guix time-machine --disable-authentication -C channels-ci.scm -- \
            system image --image-type=efi-raw --system="$ARCH" -L . \
            "$SYSTEM" 2>&1 | tee /dev/stderr | tail -1)
        [[ -f "$DISK_IMAGE" ]] || die "System image build failed"
        NEED_EXTRACT=true
    fi
else
    die "rootfs.img not found and Guix is not installed.
Download rootfs.img from the GitHub releases page and place it in the
current directory, or pass --rootfs."
fi

# ── Prepare artifacts ─────────────────────────────────────────────────────────
echo "==> Wrapping U-Boot as boot.img …"
cp "$UBOOT_BIN" "$TMPDIR/uboot-patched.bin"
# Zero EFI stub magic so the Qualcomm ABL falls through to the raw image.
printf '\x00\x00\x00\x00\x00\x00\x00\x00' \
    | dd of="$TMPDIR/uboot-patched.bin" bs=1 seek=0 conv=notrunc 2>/dev/null
mkbootimg \
    --kernel  "$TMPDIR/uboot-patched.bin" \
    --second  "$UBOOT_DTB" \
    --pagesize  $PAGESIZE \
    --base      $BASE \
    --kernel_offset  $KERNEL_OFFSET \
    --ramdisk_offset $RAMDISK_OFFSET \
    --second_offset  $SECOND_OFFSET \
    --tags_offset    $TAGS_OFFSET \
    --output "$TMPDIR/boot.img"

if [[ "$NEED_EXTRACT" == true ]]; then
    echo "==> Extracting root partition from disk image …"
    PART_INFO=$(partx -o START,SECTORS -g -n 2 "$DISK_IMAGE")
    PART_START=$(echo "$PART_INFO" | awk '{print $1}')
    PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
    [[ -n "$PART_START" && -n "$PART_SECTORS" ]] \
        || die "Could not read partition table from disk image"
    dd if="$DISK_IMAGE" of="$TMPDIR/rootfs.img" \
        bs=512 skip="$PART_START" count="$PART_SECTORS" 2>/dev/null
    ROOTFS_FLASH="$TMPDIR/rootfs.img"
    ROOTFS_MIB=$(( PART_SECTORS / 2048 ))
else
    ROOTFS_MIB=$(( $(wc -c < "$ROOTFS_FLASH") / 1024 / 1024 ))
fi

ACTUAL_LABEL=$(e2label "$ROOTFS_FLASH" 2>/dev/null || true)
if [[ "$ACTUAL_LABEL" != "guix" ]]; then
    echo "    Relabelling root partition 'guix' (was: '${ACTUAL_LABEL:-<none>}') …"
    e2label "$ROOTFS_FLASH" guix
fi

echo "==> Generating zeroed vbmeta …"
printf '\x41\x56\x42\x30\x00\x00\x01\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00' \
    | dd bs=4096 count=1 conv=sync 2>/dev/null > "$TMPDIR/vbmeta.img"

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
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Flash ─────────────────────────────────────────────────────────────────────
echo "==> Erasing dtbo_a …"
fastboot erase dtbo_a

echo "==> Flashing U-Boot to boot_a …"
fastboot flash boot_a "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification …"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"

echo "==> Flashing rootfs to userdata …"
fastboot flash userdata "$ROOTFS_FLASH"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done.  First boot initialises the Guix store (~2 min)."
echo "SSH: ssh user@172.16.42.1  (password: 123456 — change it!)"
