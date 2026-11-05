#!/usr/bin/env bash
# scripts/flash-encrypted.sh — LUKS2 assembly and flash for an encrypted system
#
# Writes: dtbo (erase), boot_a, boot_b, vbmeta_a, vbmeta_b, userdata (erase, then
# flash), active slot A.  With --output in flash.sh: nothing, it stops before.
#
# The passphrase is typed at the phone's slide-out keyboard, in the initrd: plain
# US layout, no keyd: a symbol is where a US keyboard has it (the author's
# passphrase with symbols worked, 2026-11-05).
#
# State: tested in QEMU.  The first flash on the phone (2026-11-05) sent an
# empty userdata (fastboot 7.1.2); now sent as sparse parts (mksparse.py).
# The system boots on either layout, and has the same image: nothing in it
# says encrypted (services/fde.scm).
#
# Called by flash.sh after it has handled guix shell, U-Boot, and system image
# discovery.  Not intended to be run directly.
#
# Expects (exported by flash.sh):
#   _FASTBOOT_BIN  — absolute path to fastboot binary
#   _UBOOT_BIN     — u-boot-nodtb.bin path in the Guix store
#   _UBOOT_DTB     — sm6115-fxtec-pro1x.dtb path in the Guix store
#   _DISK_IMAGE    — guix system image output (efi-raw disk image), or
#   _ROOTFS        — the root ext4 alone (flash.sh --rootfs, a CI rootfs.img)
#   _OUTPUT_DIR    — optional: write the images there and stop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for _v in _FASTBOOT_BIN _UBOOT_BIN _UBOOT_DTB; do
    [[ -n "${!_v:-}" ]] || { echo "error: $_v not set — run via flash.sh" >&2; exit 1; }
done
[[ -n "${_DISK_IMAGE:-}${_ROOTFS:-}" ]] \
    || { echo "error: _DISK_IMAGE or _ROOTFS not set — run via flash.sh" >&2; exit 1; }

ARCH="aarch64-linux"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=true; shift ;;
        *) echo "error: unknown argument: $1" >&2; exit 1 ;;
    esac
done

die()  { echo "error: $*" >&2; exit 1; }
quiet() { if [[ "$VERBOSE" == true ]]; then "$@"; else "$@" 2>/dev/null; fi; }
fastboot() { sudo "$_FASTBOOT_BIN" "$@"; }

# ── Boot image parameters (Qualcomm SM6115) ──────────────────────────────────
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100

# ── FDE layout constants ──────────────────────────────────────────────────────
BOOT_MIB=512                    # %pro1x-boot-area-mib in services/fde.scm
LUKS_PAYLOAD_MIB=16
DTB=qcom/sm6115-fxtec-pro1x.dtb
# Fixed, not --pbkdf-force-time: that would be measured on this PC and take far
# longer on the phone, at every boot.
PBKDF_ITERATIONS=4
PBKDF_MEMORY_KIB=262144

TMPDIR=$(mktemp -d)
cleanup() {
    [[ -f "$TMPDIR/volkey.bin" ]] && shred -u "$TMPDIR/volkey.bin"
    [[ -f "$TMPDIR/passphrase.bin" ]] && shred -u "$TMPDIR/passphrase.bin"
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ── Wrap U-Boot as boot.img ───────────────────────────────────────────────────
echo "==> Wrapping U-Boot as boot.img…"
cp "$_UBOOT_BIN" "$TMPDIR/u-boot.bin"
chmod +w "$TMPDIR/u-boot.bin"
printf '\x00\x00\x00\x00\x00\x00\x00\x00' \
    | quiet dd of="$TMPDIR/u-boot.bin" bs=1 seek=8 count=8 conv=notrunc
gzip --no-name -9 -c "$TMPDIR/u-boot.bin" > "$TMPDIR/u-boot.bin.gz"
cat "$TMPDIR/u-boot.bin.gz" "$_UBOOT_DTB" > "$TMPDIR/u-boot.bin.gz-dtb"
mkbootimg \
    --kernel  "$TMPDIR/u-boot.bin.gz-dtb" \
    --pagesize  $PAGESIZE --base $BASE \
    --kernel_offset  $KERNEL_OFFSET \
    --ramdisk_offset $RAMDISK_OFFSET \
    --tags_offset    $TAGS_OFFSET \
    --output "$TMPDIR/boot.img"

# ── Extract root partition ────────────────────────────────────────────────────
echo "==> Extracting root partition…"
if [[ -n "${_ROOTFS:-}" ]]; then
    cp --reflink=auto "$_ROOTFS" "$TMPDIR/root.ext4"
    chmod +w "$TMPDIR/root.ext4"
else
    PART_INFO=$(partx -o START,SECTORS -g -n 2 "$_DISK_IMAGE")
    PART_START=$(echo "$PART_INFO" | awk '{print $1}')
    PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
    [[ -n "$PART_START" && -n "$PART_SECTORS" ]] || die "Could not read partition table"
    DD_PROGRESS=(); [[ "$VERBOSE" == true ]] && DD_PROGRESS=(status=progress)
    dd if="$_DISK_IMAGE" of="$TMPDIR/root.ext4" \
        bs=512 skip="$PART_START" count="$PART_SECTORS" "${DD_PROGRESS[@]}"
fi
ROOT_MIB=$(( $(wc -c < "$TMPDIR/root.ext4") / 1048576 ))
echo "    root.ext4: ${ROOT_MIB} MiB"
ACTUAL=$(e2label "$TMPDIR/root.ext4" 2>/dev/null || true)
[[ "$ACTUAL" == "guix" ]] || e2label "$TMPDIR/root.ext4" guix

# ── Boot files ────────────────────────────────────────────────────────────
# The plain area as device/boot/pro1x-boot-menu keeps it on the phone: the image's
# own entry, with its store paths under /files, at /boot/extlinux/extlinux.conf,
# where U-Boot reads it.  From the first deploy on, the phone keeps it up to date.
echo "==> Extracting boot files…"
EXTLINUX_CONF=$(debugfs -R "cat /boot/extlinux/extlinux.conf" \
    "$TMPDIR/root.ext4" 2>/dev/null || true)
[[ -n "$EXTLINUX_CONF" ]] || die "no /boot/extlinux/extlinux.conf in the image"

field() { echo "$EXTLINUX_CONF" | awk -v f="$1" '$1 == f { print $2; exit }'; }
KERNEL_PATH=$(field KERNEL)
INITRD_PATH=$(field INITRD)
FDT_DIR=$(field FDTDIR)
[[ -n "$KERNEL_PATH" && -n "$INITRD_PATH" && -n "$FDT_DIR" ]] \
    || die "extlinux.conf lacks KERNEL, INITRD or FDTDIR"

plain_path() { echo "$1" | sed 's|^/gnu/store/|/files/|; s|/lib/dtbs$|/dtbs|'; }
BOOT_DIR="$TMPDIR/boot-area"
extract() {                     # extract IMAGE-PATH TARGET
    mkdir -p "$(dirname "$2")"
    debugfs -R "dump $1 $2" "$TMPDIR/root.ext4" 2>/dev/null
    [[ -s "$2" ]] || die "cannot read $1 from the image"
}
extract "$KERNEL_PATH" "$BOOT_DIR$(plain_path "$KERNEL_PATH")"
extract "$INITRD_PATH" "$BOOT_DIR$(plain_path "$INITRD_PATH")"
extract "$FDT_DIR/$DTB" "$BOOT_DIR$(plain_path "$FDT_DIR")/$DTB"
mkdir -p "$BOOT_DIR/boot/extlinux"
# First entry only: the image has one generation.
echo "$EXTLINUX_CONF" |
    sed 's#\(KERNEL\|INITRD\|FDTDIR\) */gnu/store/#\1 /files/#; s#/lib/dtbs$#/dtbs#' \
    > "$BOOT_DIR/boot/extlinux/extlinux.conf"
if grep -Eq '^ *(KERNEL|INITRD|FDTDIR) +/gnu/store/' "$BOOT_DIR/boot/extlinux/extlinux.conf"; then
    die "extlinux.conf still points into the store, out of U-Boot's reach"
fi

echo "==> Creating plain boot ext4 (${BOOT_MIB} MiB)…"
mke2fs -q -t ext4 -L guixboot -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$BOOT_DIR" "$TMPDIR/boot.ext4" "${BOOT_MIB}M"

# ── Passphrase ────────────────────────────────────────────────────────────────
echo ""
echo "Enter disk encryption passphrase (will not echo):"
read -rs PASSPHRASE1; echo ""
echo "Confirm passphrase:"
read -rs PASSPHRASE2; echo ""
[[ "$PASSPHRASE1" == "$PASSPHRASE2" ]] || die "passphrases do not match"
[[ -n "$PASSPHRASE1" ]]                || die "passphrase must not be empty"
PASSPHRASE="$PASSPHRASE1"
unset PASSPHRASE1 PASSPHRASE2

# ── pro1x-xts-encrypt ────────────────────────────────────────────────────────
echo "==> pro1x-xts-encrypt"
XTS_PKG=$(guix build pro1x-xts-encrypt -L "$SCRIPT_DIR/../modules" --fallback \
    2>&1 | grep '^/gnu/store' | grep -v '\.drv$' | tail -1)
XTS_ENC="$XTS_PKG/bin/pro1x-xts-encrypt"
[[ -x "$XTS_ENC" ]] || die "pro1x-xts-encrypt not found at $XTS_ENC"

# ── LUKS2 container, in place in userdata.img ─────────────────────────────
# The header alone goes through a small file; the encrypted root is written straight
# into the image, so the build needs room for root.ext4 and the image, not more.
echo "==> Creating LUKS2 header…"
ROOT_SIZE=$(wc -c < "$TMPDIR/root.ext4")
truncate -s "$(( LUKS_PAYLOAD_MIB + 1 ))M" "$TMPDIR/luks-header.bin"
dd if=/dev/urandom of="$TMPDIR/volkey.bin"          bs=64  count=1          2>/dev/null
printf '%s' "$PASSPHRASE" > "$TMPDIR/passphrase.bin"
unset PASSPHRASE
cryptsetup luksFormat \
    --type luks2 --cipher aes-xts-plain64 --key-size 512 \
    --hash sha256 --pbkdf argon2id \
    --pbkdf-memory "$PBKDF_MEMORY_KIB" --pbkdf-parallel 1 \
    --pbkdf-force-iterations "$PBKDF_ITERATIONS" \
    --sector-size 512 --align-payload 32768 \
    --volume-key-file "$TMPDIR/volkey.bin" \
    --key-file        "$TMPDIR/passphrase.bin" \
    --batch-mode "$TMPDIR/luks-header.bin"
shred -u "$TMPDIR/passphrase.bin"

PAYLOAD_BYTES=$(cryptsetup luksDump "$TMPDIR/luks-header.bin" 2>/dev/null | \
    awk '/Data segments:/{f=1} f && /offset:/{gsub(/[^0-9]/,"",$2); print $2; exit}')
[[ -n "$PAYLOAD_BYTES" ]] || die "cannot read the LUKS2 payload offset"
echo "    LUKS2 payload offset: $(( PAYLOAD_BYTES / 1024 / 1024 )) MiB"

echo "==> Assembling userdata image…"
BOOT_BYTES=$(( BOOT_MIB * 1024 * 1024 ))
TOTAL_MIB=$(( BOOT_MIB + PAYLOAD_BYTES / (1024*1024) + (ROOT_SIZE + 1024*1024 - 1) / (1024*1024) ))
truncate -s "${TOTAL_MIB}M" "$TMPDIR/userdata.img"
dd if="$TMPDIR/boot.ext4"       of="$TMPDIR/userdata.img" bs=1M conv=notrunc 2>/dev/null
dd if="$TMPDIR/luks-header.bin" of="$TMPDIR/userdata.img" bs=1M seek="$BOOT_MIB" \
    count="$(( PAYLOAD_BYTES / (1024*1024) ))" conv=notrunc 2>/dev/null

echo "==> Encrypting root partition…"
"$XTS_ENC" "$TMPDIR/volkey.bin" "$TMPDIR/userdata.img" \
    "$(( BOOT_BYTES + PAYLOAD_BYTES ))" < "$TMPDIR/root.ext4"
shred -u "$TMPDIR/volkey.bin"
rm -f "$TMPDIR/root.ext4"
echo "    ${TOTAL_MIB} MiB  (${BOOT_MIB} MiB plain boot + $(( TOTAL_MIB - BOOT_MIB )) MiB LUKS)"

# ── vbmeta ────────────────────────────────────────────────────────────────────
python3 -c "
import struct, sys
HEADER = ('>4s''II''Q''Q''I''QQ''QQ''QQ''QQ''QQ''Q''I''I''48s''80x')
hdr = struct.pack(HEADER, b'AVB0',1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    2,0,b'pro1x-guix'.ljust(48,b'\x00'))
sys.stdout.buffer.write(hdr.ljust(4096,b'\x00'))
" > "$TMPDIR/vbmeta.img"

# ── Confirm & flash ───────────────────────────────────────────────────────────
if [[ -n "${_OUTPUT_DIR:-}" ]]; then
    mkdir -p "$_OUTPUT_DIR"
    mv "$TMPDIR/boot.img" "$TMPDIR/vbmeta.img" "$TMPDIR/userdata.img" "$_OUTPUT_DIR/"
    echo "==> Wrote $_OUTPUT_DIR; nothing flashed."
    exit 0
fi

# Fastboot 7.1.2 read this image as empty when it split it itself, and sent
# 0 KB (2026-11-05: the phone then had no /boot/extlinux/extlinux.conf).  So
# the image goes as sparse parts under the download limit, made here.
echo "==> Splitting userdata.img into sparse parts…"
python3 "$SCRIPT_DIR/mksparse.py" --consume "$TMPDIR/userdata.img" "$TMPDIR/userdata" \
    > "$TMPDIR/parts.txt"
rm -f "$TMPDIR/userdata.img"
mapfile -t PARTS < "$TMPDIR/parts.txt"
(( ${#PARTS[@]} > 0 )) || die "no sparse parts written"
echo ""
echo "==> All artifacts ready — device must be in fastboot mode."
echo "    boot.img:     $TMPDIR/boot.img"
echo "    userdata:     ${#PARTS[@]} sparse parts  (${TOTAL_MIB} MiB)"
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
CONFIRM="${CONFIRM//$'\r'/}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "==> Erasing dtbo…"
fastboot erase dtbo

echo "==> Flashing U-Boot to both slots…"
fastboot flash boot_a "$TMPDIR/boot.img"
fastboot flash boot_b "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification…"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"
fastboot flash vbmeta_b "$TMPDIR/vbmeta.img"

# The image ends long before the partition: without this, the old system's
# unencrypted data stays on the flash behind it.
echo "==> Erasing userdata…"
fastboot erase userdata

echo "==> Flashing userdata (${#PARTS[@]} parts)…"
for p in "${PARTS[@]}"; do
    fastboot flash userdata "$p" || die "flashing $p failed"
done

echo "==> Setting active slot to A…"
fastboot set_active a

echo "==> Rebooting…"
fastboot reboot

echo ""
echo "Done.  Open the keyboard and type the passphrase when the screen asks."
echo "SSH (after boot): ssh user@172.16.42.1  (password: 123456 — change it!)"
