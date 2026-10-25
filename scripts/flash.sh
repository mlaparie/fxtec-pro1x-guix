#!/usr/bin/env bash
# scripts/flash.sh — initial flash of a Guix system onto the F(x)tec Pro1X
#
# Usage (from repo root, device in fastboot mode):
#   bash scripts/flash.sh systems/minimal.scm
#   bash scripts/flash.sh systems/mobile.scm
#
# What it does:
#   Phase 1 — Build: U-Boot and the Guix system image (both must succeed)
#   Phase 2 — Prepare: wrap U-Boot as boot.img, extract root ext4 partition
#   Phase 3 — Verify: confirm all artifacts are present and non-empty
#   Phase 4 — Flash: prompt once, then flash atomically
#
# Requirements on the build machine:
#   • Guix (with the fxtec-pro1x and nonguix channels in channels.scm)
#   • fastboot, mkbootimg  (guix shell -m manifest.scm -- bash scripts/flash.sh …)
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
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found — run: guix shell -m manifest.scm -- bash $0 $*"; }

# Check tools before spending time building
need fastboot
need mkbootimg

# ── Phase 1: Find or build artifacts ─────────────────────────────────────────
# Check the store first — avoids triggering a cross-gcc rebuild when the
# output is already there (e.g. built via guix time-machine separately).
echo "==> [1/2] Finding U-Boot …"
UBOOT=$(find /gnu/store -maxdepth 1 -name "*-u-boot-pro1x-*" \
    ! -name "*.drv" ! -name "*-checkout" ! -name "*-builder" ! -name "*lock*" \
    2>/dev/null | sort | tail -1)
if [ -d "$UBOOT" ]; then
    echo "    Using cached: $UBOOT"
else
    echo "    Not found in store — building …"
    UBOOT=$(guix time-machine --disable-authentication -C channels-ci.scm -- \
        build u-boot-pro1x -L . --no-grafts 2>&1 | tee /dev/stderr | tail -1)
    [ -d "$UBOOT" ] || die "U-Boot build failed — cannot flash"
fi
[ -f "$UBOOT/libexec/u-boot.bin" ]              || die "u-boot.bin missing from store output"
[ -f "$UBOOT/libexec/sm6115-fxtec-pro1x.dtb" ] || die "DTB missing from store output"
echo "    $UBOOT"

echo "==> [2/2] Finding system image ($SYSTEM) …"
DISK_IMAGE=$(find /gnu/store -maxdepth 1 -name "*-disk-image" \
    ! -name "*.drv" 2>/dev/null | sort | tail -1)
if [ -f "$DISK_IMAGE" ]; then
    echo "    Using cached: $DISK_IMAGE"
else
    echo "    Not found in store — building …"
    DISK_IMAGE=$(guix time-machine --disable-authentication -C channels-ci.scm -- \
        system image --image-type=efi-raw --system="$ARCH" -L . \
        "$SYSTEM" 2>&1 | tee /dev/stderr | tail -1)
    [ -f "$DISK_IMAGE" ] || die "System image build failed — cannot flash"
fi

# ── Phase 2: Prepare artifacts ───────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Wrapping U-Boot as boot.img …"
UBOOT_BIN="$UBOOT/libexec/u-boot.bin"
UBOOT_DTB="$UBOOT/libexec/sm6115-fxtec-pro1x.dtb"
cp "$UBOOT_BIN" "$TMPDIR/uboot-patched.bin"
# Zero EFI stub magic so ABL falls through to the raw U-Boot image
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

echo "==> Extracting root partition from disk image …"
PART_INFO=$(partx -o START,SECTORS -g -n 2 "$DISK_IMAGE")
PART_START=$(echo "$PART_INFO" | awk '{print $1}')
PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
[ -n "$PART_START" ] && [ -n "$PART_SECTORS" ] || die "Could not read partition table from disk image"
dd if="$DISK_IMAGE" of="$TMPDIR/rootfs.img" \
    bs=512 skip="$PART_START" count="$PART_SECTORS" 2>/dev/null
ACTUAL_LABEL=$(e2label "$TMPDIR/rootfs.img" 2>/dev/null || true)
if [ "$ACTUAL_LABEL" != "guix" ]; then
    echo "    Relabelling root partition 'guix' (was: '${ACTUAL_LABEL:-<none>}') …"
    e2label "$TMPDIR/rootfs.img" guix
fi

echo "==> Generating zeroed vbmeta …"
printf '\x41\x56\x42\x30\x00\x00\x01\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00' | \
    dd bs=4096 count=1 conv=sync 2>/dev/null > "$TMPDIR/vbmeta.img"

# ── Phase 3: Verify ───────────────────────────────────────────────────────────
BOOT_SIZE=$(wc -c < "$TMPDIR/boot.img")
ROOTFS_MIB=$(( PART_SECTORS / 2048 ))
[ "$BOOT_SIZE"  -gt 0 ] || die "boot.img is empty"
[ "$ROOTFS_MIB" -gt 0 ] || die "rootfs.img is empty"

echo ""
echo "==> All artifacts ready — device must be in fastboot mode before continuing."
echo "    boot.img : $TMPDIR/boot.img  ($(( BOOT_SIZE / 1024 )) KiB)"
echo "    rootfs   : $TMPDIR/rootfs.img  ($ROOTFS_MIB MiB)"
echo "    vbmeta   : $TMPDIR/vbmeta.img"
echo ""
echo "    Flashing will erase userdata and replace the bootloader on slot A."
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Phase 4: Flash ────────────────────────────────────────────────────────────
echo "==> Erasing dtbo_a …"
fastboot erase dtbo_a

echo "==> Flashing U-Boot to boot_a …"
fastboot flash boot_a "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification …"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"

echo "==> Flashing rootfs to userdata …"
fastboot flash userdata "$TMPDIR/rootfs.img"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done.  First boot initialises the Guix store (~2 min)."
echo "SSH: ssh user@172.16.42.1  (password: 123456 — change it!)"
