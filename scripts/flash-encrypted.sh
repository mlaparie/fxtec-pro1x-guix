#!/usr/bin/env bash
# scripts/flash-encrypted.sh — LUKS2 assembly and flash for mobile-encrypted.scm
#
# Called by flash.sh after it has handled guix shell, U-Boot, and system image
# discovery.  Not intended to be run directly.
#
# Expects (exported by flash.sh):
#   _FASTBOOT_BIN  — absolute path to fastboot binary
#   _UBOOT_BIN     — u-boot-nodtb.bin path in the Guix store
#   _UBOOT_DTB     — sm6115-fxtec-pro1x.dtb path in the Guix store
#   _DISK_IMAGE    — guix system image output (efi-raw disk image)
#
# After guix system reconfigure: bash scripts/update-encrypted-boot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for _v in _FASTBOOT_BIN _UBOOT_BIN _UBOOT_DTB _DISK_IMAGE; do
    [[ -n "${!_v:-}" ]] || { echo "error: $_v not set — run via flash.sh" >&2; exit 1; }
done

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
BOOT_MIB=256
LUKS_PAYLOAD_MIB=16
BOOT_SECTORS=$(( BOOT_MIB * 2048 ))

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

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
PART_INFO=$(partx -o START,SECTORS -g -n 2 "$_DISK_IMAGE")
PART_START=$(echo "$PART_INFO" | awk '{print $1}')
PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
[[ -n "$PART_START" && -n "$PART_SECTORS" ]] || die "Could not read partition table"
DD_PROGRESS=(); [[ "$VERBOSE" == true ]] && DD_PROGRESS=(status=progress)
dd if="$_DISK_IMAGE" of="$TMPDIR/root.ext4" \
    bs=512 skip="$PART_START" count="$PART_SECTORS" "${DD_PROGRESS[@]}"
ROOT_MIB=$(( PART_SECTORS / 2048 ))
echo "    root.ext4: ${ROOT_MIB} MiB"
ACTUAL=$(e2label "$TMPDIR/root.ext4" 2>/dev/null || true)
[[ "$ACTUAL" == "guix" ]] || e2label "$TMPDIR/root.ext4" guix

# ── Extract boot files ────────────────────────────────────────────────────────
echo "==> Extracting boot files…"
EXTLINUX_CONF=$(debugfs -R "cat /boot/extlinux/extlinux.conf" \
    "$TMPDIR/root.ext4" 2>/dev/null || true)

if [[ -z "$EXTLINUX_CONF" ]]; then
    echo "    (no extlinux.conf in image — using default kernel arguments)"
    APPEND_LINE="console=tty1 loglevel=4 \
g_cdc.host_addr=02:50:31:e8:00:01 g_cdc.dev_addr=02:50:31:e8:00:02"
else
    APPEND_LINE=$(echo "$EXTLINUX_CONF" | grep -i '^\s*APPEND' | head -1 | \
        sed 's/^\s*APPEND\s*//')
fi

KERNEL_PATH=$(echo "$EXTLINUX_CONF" | grep -i '^\s*KERNEL\s' | head -1 | awk '{print $2}') || true
[[ -n "$KERNEL_PATH" ]] && \
    debugfs -R "dump $KERNEL_PATH $TMPDIR/vmlinuz" "$TMPDIR/root.ext4" 2>/dev/null || true

if [[ ! -s "$TMPDIR/vmlinuz" ]]; then
    SYS=$(guix system build --system="$ARCH" -L "$SCRIPT_DIR/../modules" \
        systems/mobile-encrypted.scm 2>/dev/null | grep '^/gnu/store' | tail -1)
    for name in Image Image.gz bzImage; do
        [[ -f "$SYS/kernel/$name" ]] && cp "$SYS/kernel/$name" "$TMPDIR/vmlinuz" && break
    done
    [[ -s "$TMPDIR/vmlinuz" ]] || die "cannot locate kernel binary"
fi

INITRD_PATH=$(echo "$EXTLINUX_CONF" | grep -i '^\s*INITRD\s' | head -1 | awk '{print $2}') || true
[[ -n "$INITRD_PATH" ]] && \
    debugfs -R "dump $INITRD_PATH $TMPDIR/initrd.img" "$TMPDIR/root.ext4" 2>/dev/null || true
if [[ ! -s "$TMPDIR/initrd.img" ]]; then
    SYS=${SYS:-$(guix system build --system="$ARCH" -L "$SCRIPT_DIR/../modules" \
        systems/mobile-encrypted.scm 2>/dev/null | grep '^/gnu/store' | tail -1)}
    cp "$(readlink -f "$SYS/initrd")" "$TMPDIR/initrd.img"
fi

echo "    kernel: $(( $(wc -c < "$TMPDIR/vmlinuz")   / 1024 / 1024 + 1 )) MiB" \
     "  initrd: $(( $(wc -c < "$TMPDIR/initrd.img") / 1024 / 1024 + 1 )) MiB"

# ── Plain boot ext4 ───────────────────────────────────────────────────────────
echo "==> Creating plain boot ext4 (${BOOT_MIB} MiB)…"
dd if=/dev/zero of="$TMPDIR/boot.ext4" bs=1M count="$BOOT_MIB" 2>/dev/null
mke2fs -t ext4 -L guixboot -E lazy_itable_init=0,lazy_journal_init=0 \
    "$TMPDIR/boot.ext4" 2>/dev/null
for cmd in "mkdir /boot" "mkdir /boot/extlinux" \
           "write $TMPDIR/vmlinuz /vmlinuz" \
           "write $TMPDIR/initrd.img /initrd.img"; do
    debugfs -w "$TMPDIR/boot.ext4" -R "$cmd" 2>/dev/null
done
cat > "$TMPDIR/extlinux.conf" <<EOF
TIMEOUT 30
PROMPT 1
DEFAULT guix

LABEL guix
  MENU LABEL GNU Guix
  KERNEL /vmlinuz
  INITRD /initrd.img
  APPEND $APPEND_LINE
EOF
debugfs -w "$TMPDIR/boot.ext4" \
    -R "write $TMPDIR/extlinux.conf /boot/extlinux/extlinux.conf" 2>/dev/null

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

# ── LUKS2 container ───────────────────────────────────────────────────────────
echo "==> Creating LUKS2 container…"
ROOT_SIZE=$(wc -c < "$TMPDIR/root.ext4")
LUKS_MIB=$(( LUKS_PAYLOAD_MIB + (ROOT_SIZE + 1024*1024 - 1) / (1024*1024) ))
dd if=/dev/zero    of="$TMPDIR/luks-container.bin" bs=1M count="$LUKS_MIB" 2>/dev/null
dd if=/dev/urandom of="$TMPDIR/volkey.bin"          bs=64  count=1          2>/dev/null
printf '%s' "$PASSPHRASE" > "$TMPDIR/passphrase.bin"
unset PASSPHRASE
cryptsetup luksFormat \
    --type luks2 --cipher aes-xts-plain64 --key-size 512 \
    --hash sha256 --pbkdf argon2id \
    --pbkdf-memory 65536 --pbkdf-parallel 1 --pbkdf-time-ms 2000 \
    --sector-size 512 --align-payload 32768 \
    --volume-key-file "$TMPDIR/volkey.bin" \
    --key-file        "$TMPDIR/passphrase.bin" \
    --batch-mode "$TMPDIR/luks-container.bin"
shred -u "$TMPDIR/passphrase.bin"

PAYLOAD_BYTES=$(cryptsetup luksDump "$TMPDIR/luks-container.bin" 2>/dev/null | \
    awk '/Data segments:/{f=1} f && /offset:/{gsub(/[^0-9]/,"",$2); print $2; exit}')
[[ -n "$PAYLOAD_BYTES" ]] || PAYLOAD_BYTES=$(( LUKS_PAYLOAD_MIB * 1024 * 1024 ))
echo "    LUKS2 payload offset: $(( PAYLOAD_BYTES / 1024 / 1024 )) MiB"

echo "==> Encrypting root partition…"
"$XTS_ENC" "$TMPDIR/volkey.bin" "$TMPDIR/luks-container.bin" \
    "$PAYLOAD_BYTES" < "$TMPDIR/root.ext4"
shred -u "$TMPDIR/volkey.bin"

# ── Assemble userdata.img ─────────────────────────────────────────────────────
echo "==> Assembling userdata image…"
LUKS_SIZE=$(wc -c < "$TMPDIR/luks-container.bin")
TOTAL_MIB=$(( BOOT_MIB + (LUKS_SIZE + 1024*1024 - 1) / (1024*1024) ))
dd if=/dev/zero of="$TMPDIR/userdata.img" bs=1M count="$TOTAL_MIB" 2>/dev/null
dd if="$TMPDIR/boot.ext4"          of="$TMPDIR/userdata.img" bs=512 seek=0             conv=notrunc 2>/dev/null
dd if="$TMPDIR/luks-container.bin" of="$TMPDIR/userdata.img" bs=512 seek="$BOOT_SECTORS" conv=notrunc 2>/dev/null
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
echo ""
echo "==> All artifacts ready — device must be in fastboot mode."
echo "    boot.img:     $TMPDIR/boot.img"
echo "    userdata.img: $TMPDIR/userdata.img  (${TOTAL_MIB} MiB)"
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

echo "==> Flashing userdata…"
fastboot flash userdata "$TMPDIR/userdata.img"

echo "==> Setting active slot to A…"
fastboot set_active a

echo "==> Rebooting…"
fastboot reboot

echo ""
echo "Done.  Enter the encryption passphrase when prompted by the initrd."
echo "SSH (after boot): ssh user@172.16.42.1  (password: 123456 — change it!)"
