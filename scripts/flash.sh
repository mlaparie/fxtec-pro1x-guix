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
#   • fastboot (guix shell fastboot -- bash scripts/flash.sh …)
#   • mkbootimg (guix shell mkbootimg fastboot -- bash scripts/flash.sh …)
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
    --no-grafts 2>&1 | tee /dev/stderr | tail -1)
# Fallback: if build failed (cross-gcc stmp-fixinc issue on non-FHS hosts),
# use any already-built u-boot-pro1x output from the store.
if [ ! -d "$UBOOT" ]; then
    echo "    Build failed; falling back to cached store output …"
    UBOOT=$(find /gnu/store -maxdepth 1 -name "*-u-boot-pro1x-*" \
        ! -name "*.drv" ! -name "*-checkout" ! -name "*-builder" ! -name "*lock*" \
        2>/dev/null | sort | tail -1)
    [ -d "$UBOOT" ] || die "U-Boot not in store and build failed — see scripts/flash.sh"
fi
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
DISK_IMAGE=$(guix system image \
    --image-type=efi-raw \
    --system="$ARCH" \
    -L . \
    "$SYSTEM" 2>&1 | tee /dev/stderr | tail -1)
echo "    $DISK_IMAGE"

# Extract the root ext4 partition (partition 2 in efi-raw GPT layout) so we
# can flash just the filesystem — no partition table — to the userdata slot.
echo "==> Extracting root partition from disk image …"
PART_INFO=$(partx -o START,SECTORS -g -n 2 "$DISK_IMAGE")
PART_START=$(echo "$PART_INFO" | awk '{print $1}')
PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
dd if="$DISK_IMAGE" of="$TMPDIR/rootfs.img" \
    bs=512 skip="$PART_START" count="$PART_SECTORS" 2>/dev/null
echo "    $TMPDIR/rootfs.img ($(( PART_SECTORS / 2048 )) MiB)"

# The system config mounts by label "guix"; ensure the extracted partition
# carries that label (Guix's image builder should set it, but verify).
ACTUAL_LABEL=$(e2label "$TMPDIR/rootfs.img" 2>/dev/null || true)
if [ "$ACTUAL_LABEL" != "guix" ]; then
    echo "==> Relabelling root partition 'guix' (was: '${ACTUAL_LABEL:-<none>}') …"
    e2label "$TMPDIR/rootfs.img" guix
fi

echo ""
echo "==> Ready to flash.  Device must be in fastboot mode."
echo "    boot.img:  $TMPDIR/boot.img"
echo "    rootfs:    $TMPDIR/rootfs.img"
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "==> Erasing dtbo_a (clears Android DT overlay that can prevent boot) …"
fastboot erase dtbo_a

echo "==> Flashing U-Boot to boot_a …"
fastboot flash boot_a "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification …"
printf '\x41\x56\x42\x30\x00\x00\x01\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00' | \
    dd bs=4096 count=1 conv=sync 2>/dev/null > "$TMPDIR/vbmeta.img"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"

echo "==> Flashing rootfs to userdata …"
fastboot flash userdata "$TMPDIR/rootfs.img"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done.  First boot initialises the Guix store; allow ~2 minutes."
echo "SSH: ssh user@172.16.42.1  (password: 123456 — change it!)"
