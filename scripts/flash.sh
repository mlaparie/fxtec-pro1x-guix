#!/usr/bin/env bash
# scripts/flash.sh — initial flash of a Guix system onto the F(x)tec Pro1X
#
# Usage (from repo root, device in fastboot mode):
#   bash scripts/flash.sh systems/minimal.scm
#   bash scripts/flash.sh systems/phosh.scm
#
# What it does:
#   1. Builds U-Boot (wrapped as an Android boot image for the ABL)
#   2. Builds a Guix ext4 disk image for the rootfs
#   3. Flashes both over fastboot
#
# Requirements on the build machine:
#   • Guix (with the fxtec-pro1x and nonguix channels in channels.scm)
#   • fastboot (android-tools)
#   • mkbootimg (android-tools)
#   • aarch64-linux cross-compilation support or an aarch64 offload machine

set -euo pipefail

SYSTEM="${1:-systems/minimal.scm}"
ARCH="aarch64-linux"

# ── Boot image parameters (from lib/bootimg.nix) ────────────────────────────
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found (install android-tools)"; }
need fastboot
need mkbootimg

echo "==> Building U-Boot …"
UBOOT=$(guix build u-boot-pro1x \
    --system="$ARCH" \
    -L . \
    --no-grafts 2>&1 | tail -1)
echo "    $UBOOT"

UBOOT_BIN="$UBOOT/libexec/u-boot.bin"
UBOOT_DTB="$UBOOT/libexec/sm6115-fxtec-pro1x.dtb"

# The stock ABL expects an Android boot image.  U-Boot's EFI stub header
# confuses it, so we zero the first 8 bytes (magic) after wrapping.
echo "==> Wrapping U-Boot as boot.img …"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Copy and zero the EFI stub magic so ABL falls through to the raw image
cp "$UBOOT_BIN" "$TMPDIR/uboot-patched.bin"
printf '\x00\x00\x00\x00\x00\x00\x00\x00' | dd of="$TMPDIR/uboot-patched.bin" bs=1 seek=0 conv=notrunc 2>/dev/null

mkbootimg \
    --kernel "$TMPDIR/uboot-patched.bin" \
    --second "$UBOOT_DTB" \
    --pagesize $PAGESIZE \
    --base $BASE \
    --kernel_offset $KERNEL_OFFSET \
    --ramdisk_offset $RAMDISK_OFFSET \
    --second_offset $SECOND_OFFSET \
    --tags_offset $TAGS_OFFSET \
    --output "$TMPDIR/boot.img"

echo "==> Building Guix system image for $SYSTEM …"
IMAGE=$(guix system image \
    --image-type=ext4 \
    --system="$ARCH" \
    -L . \
    "$SYSTEM" 2>&1 | tail -1)
echo "    $IMAGE"

echo ""
echo "==> Ready to flash.  Device must be in fastboot mode."
echo "    boot.img:  $TMPDIR/boot.img"
echo "    rootfs:    $IMAGE"
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "==> Flashing U-Boot to boot_a …"
fastboot flash boot_a "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification …"
fastboot flash vbmeta_a \
    <(printf '\x41\x56\x42\x30\x00\x00\x01\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00' | \
     dd bs=4096 count=1 conv=sync 2>/dev/null)

echo "==> Flashing rootfs to userdata …"
fastboot flash userdata "$IMAGE"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done.  First boot initialises the Guix store; allow ~2 minutes."
echo "SSH: ssh user@172.16.42.1  (password: user — change it!)"
