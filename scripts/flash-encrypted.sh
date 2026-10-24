#!/usr/bin/env bash
# scripts/flash-encrypted.sh — flash a LUKS2-encrypted Guix system onto the Pro1X
#
# Usage (from repo root, device in fastboot mode):
#   bash scripts/flash-encrypted.sh systems/phosh-encrypted.scm
#
# Partition layout written to /dev/disk/by-partlabel/userdata:
#   [0,  256 MiB) : plain ext4 "guixboot" — U-Boot reads extlinux.conf + kernel here
#   [256 MiB, …)  : LUKS2 header + encrypted ext4 root
#
# Requirements:
#   • Guix (fxtec-pro1x + nonguix channels)
#   • fastboot, mkbootimg (android-tools)
#   • partx, dd, e2label (util-linux, e2fsprogs)
#   • debugfs, mke2fs  (e2fsprogs) — to build the plain boot ext4 without root
#   • cryptsetup — to create the LUKS2 header (no root needed for luksFormat on a file)
#   • aarch64-linux cross-compilation support or an aarch64 offload machine
#
# The encryption step uses pro1x-xts-encrypt from device/fde/xts-encrypt.c
# (built automatically from source) — no root, no device-mapper needed.

set -euo pipefail

SYSTEM="${1:-systems/phosh-encrypted.scm}"
ARCH="aarch64-linux"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Boot image parameters (from flash.sh) ────────────────────────────────────
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100

# ── FDE layout constants ──────────────────────────────────────────────────────
BOOT_MIB=256                    # plain ext4 size (kernel + initrd + extlinux.conf)
LUKS_PAYLOAD_MIB=16             # LUKS2 header + keyslots (--align-payload=32768)
BOOT_SECTORS=$(( BOOT_MIB * 2048 ))   # = 524288

die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }
need fastboot
need mkbootimg
need partx
need mke2fs
need debugfs
need cryptsetup

echo "==> Building U-Boot …"
UBOOT=$(guix build u-boot-pro1x \
    --system="$ARCH" \
    -L "$REPO_ROOT" \
    --no-grafts 2>&1 | tail -1)
echo "    $UBOOT"

UBOOT_BIN="$UBOOT/libexec/u-boot.bin"
UBOOT_DTB="$UBOOT/libexec/sm6115-fxtec-pro1x.dtb"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Wrap U-Boot as boot.img ──────────────────────────────────────────────────
echo "==> Wrapping U-Boot as boot.img …"
cp "$UBOOT_BIN" "$TMPDIR/uboot-patched.bin"
printf '\x00\x00\x00\x00\x00\x00\x00\x00' | \
    dd of="$TMPDIR/uboot-patched.bin" bs=1 seek=0 conv=notrunc 2>/dev/null

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

# ── Build Guix system image ──────────────────────────────────────────────────
echo "==> Building Guix system image for $SYSTEM …"
DISK_IMAGE=$(guix system image \
    --image-type=efi-raw \
    --system="$ARCH" \
    -L "$REPO_ROOT" \
    "$SYSTEM" 2>&1 | tail -1)
echo "    $DISK_IMAGE"

# ── Extract root partition (partition 2 in efi-raw GPT) ──────────────────────
echo "==> Extracting root partition …"
PART_INFO=$(partx -o START,SECTORS -g -n 2 "$DISK_IMAGE")
PART_START=$(echo "$PART_INFO" | awk '{print $1}')
PART_SECTORS=$(echo "$PART_INFO" | awk '{print $2}')
dd if="$DISK_IMAGE" of="$TMPDIR/root.ext4" \
    bs=512 skip="$PART_START" count="$PART_SECTORS" 2>/dev/null
ROOT_MIB=$(( PART_SECTORS / 2048 ))
echo "    root.ext4: ${ROOT_MIB} MiB"

# Verify label is "guix" (set by the system image builder).
ACTUAL=$(e2label "$TMPDIR/root.ext4" 2>/dev/null || true)
[ "$ACTUAL" = "guix" ] || e2label "$TMPDIR/root.ext4" guix

# ── Extract boot files from root.ext4 ────────────────────────────────────────
# Pull extlinux.conf, kernel, and initrd out of the root image so U-Boot can
# read them from the plain (unencrypted) boot area.
echo "==> Extracting boot files from root image …"

# Get the kernel APPEND line from the generated extlinux.conf.
EXTLINUX_CONF=$(debugfs -R "cat /boot/extlinux/extlinux.conf" \
    "$TMPDIR/root.ext4" 2>/dev/null || true)

if [ -z "$EXTLINUX_CONF" ]; then
    # extlinux.conf is written at reconfigure time, not baked into the image.
    # Derive the APPEND line from the system build parameters directly.
    echo "    (no extlinux.conf in image — generating from system parameters)"
    APPEND_LINE="console=ttyMSM0,115200n8 console=tty1 loglevel=4 \
g_cdc.host_addr=02:50:31:e8:00:01 g_cdc.dev_addr=02:50:31:e8:00:02"
else
    APPEND_LINE=$(echo "$EXTLINUX_CONF" | grep -i '^\s*APPEND' | head -1 | \
        sed 's/^\s*APPEND\s*//')
fi

# Kernel binary: look for Image (aarch64 uncompressed) or bzImage.
KERNEL_STORE_PATH=$(echo "$EXTLINUX_CONF" | \
    grep -i '^\s*KERNEL\s' | head -1 | awk '{print $2}') || true

if [ -n "$KERNEL_STORE_PATH" ]; then
    echo "    kernel: $KERNEL_STORE_PATH"
    debugfs -R "dump $KERNEL_STORE_PATH $TMPDIR/vmlinuz" \
        "$TMPDIR/root.ext4" 2>/dev/null
fi

# Fall back to the known store path symlinks in the system build.
if [ ! -s "$TMPDIR/vmlinuz" ]; then
    SYSTEM_PATH=$(guix system build --system="$ARCH" -L "$REPO_ROOT" \
        "$SYSTEM" 2>&1 | tail -1)
    KERNEL_PROF=$(readlink -f "$SYSTEM_PATH/kernel")
    for name in Image Image.gz bzImage; do
        if [ -f "$KERNEL_PROF/$name" ]; then
            cp "$KERNEL_PROF/$name" "$TMPDIR/vmlinuz"
            echo "    kernel: $KERNEL_PROF/$name"
            break
        fi
    done
    [ -s "$TMPDIR/vmlinuz" ] || die "cannot locate kernel binary"
fi

# initrd: extract from the root image or copy from the system store path.
INITRD_STORE_PATH=$(echo "$EXTLINUX_CONF" | \
    grep -i '^\s*INITRD\s' | head -1 | awk '{print $2}') || true

if [ -n "$INITRD_STORE_PATH" ]; then
    debugfs -R "dump $INITRD_STORE_PATH $TMPDIR/initrd.img" \
        "$TMPDIR/root.ext4" 2>/dev/null
fi

if [ ! -s "$TMPDIR/initrd.img" ]; then
    SYSTEM_PATH=${SYSTEM_PATH:-$(guix system build --system="$ARCH" \
        -L "$REPO_ROOT" "$SYSTEM" 2>&1 | tail -1)}
    INITRD_PATH=$(readlink -f "$SYSTEM_PATH/initrd")
    cp "$INITRD_PATH" "$TMPDIR/initrd.img"
    echo "    initrd: $INITRD_PATH"
fi

KERNEL_MIB=$(( $(wc -c < "$TMPDIR/vmlinuz") / 1024 / 1024 + 1 ))
INITRD_MIB=$(( $(wc -c < "$TMPDIR/initrd.img") / 1024 / 1024 + 1 ))
echo "    kernel: ${KERNEL_MIB} MiB   initrd: ${INITRD_MIB} MiB"

# ── Create plain boot ext4 ────────────────────────────────────────────────────
echo "==> Creating plain boot ext4 (${BOOT_MIB} MiB) …"
dd if=/dev/zero of="$TMPDIR/boot.ext4" bs=1M count="$BOOT_MIB" 2>/dev/null
mke2fs -t ext4 -L guixboot \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    "$TMPDIR/boot.ext4" 2>/dev/null

# Populate with kernel, initrd, and extlinux.conf (using debugfs — no root).
debugfs -w "$TMPDIR/boot.ext4" -R "mkdir /boot"       2>/dev/null
debugfs -w "$TMPDIR/boot.ext4" -R "mkdir /boot/extlinux" 2>/dev/null
debugfs -w "$TMPDIR/boot.ext4" -R "write $TMPDIR/vmlinuz /vmlinuz" 2>/dev/null
debugfs -w "$TMPDIR/boot.ext4" -R "write $TMPDIR/initrd.img /initrd.img" 2>/dev/null

# Write a simple extlinux.conf that references the fixed /vmlinuz and /initrd.img.
cat > "$TMPDIR/extlinux.conf" << EOF
# Generated by scripts/flash-encrypted.sh.
# After guix system reconfigure, run scripts/update-encrypted-boot.sh.
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
echo "    done."

# ── Get passphrase ────────────────────────────────────────────────────────────
echo ""
echo "Enter the disk encryption passphrase (will not echo):"
read -rs PASSPHRASE1
echo ""
echo "Confirm passphrase:"
read -rs PASSPHRASE2
echo ""
[ "$PASSPHRASE1" = "$PASSPHRASE2" ] || die "passphrases do not match"
[ -n "$PASSPHRASE1" ] || die "passphrase must not be empty"
PASSPHRASE="$PASSPHRASE1"
unset PASSPHRASE1 PASSPHRASE2

# ── Build pro1x-xts-encrypt ──────────────────────────────────────────────────
echo "==> Building pro1x-xts-encrypt …"
SSL_PATH=$(guix build openssl -L "$REPO_ROOT" 2>&1 | tail -1)
XTS_ENC="$TMPDIR/pro1x-xts-encrypt"
guix shell openssl gcc-toolchain -- \
    gcc -O2 \
    -o "$XTS_ENC" \
    "$REPO_ROOT/device/fde/xts-encrypt.c" \
    "-I$SSL_PATH/include" \
    "-L$SSL_PATH/lib" \
    -lcrypto
echo "    $XTS_ENC"

# ── Create LUKS2 container ────────────────────────────────────────────────────
echo "==> Creating LUKS2 container …"
ROOT_SIZE=$(wc -c < "$TMPDIR/root.ext4")
LUKS_MIB=$(( LUKS_PAYLOAD_MIB + (ROOT_SIZE + 1024*1024 - 1) / (1024*1024) ))

dd if=/dev/zero of="$TMPDIR/luks-container.bin" bs=1M count="$LUKS_MIB" 2>/dev/null

# Generate random 64-byte AES-XTS volume key.
dd if=/dev/urandom of="$TMPDIR/volkey.bin" bs=64 count=1 2>/dev/null

# Write passphrase to a temp file for cryptsetup.
printf '%s' "$PASSPHRASE" > "$TMPDIR/passphrase.bin"
unset PASSPHRASE

# Format LUKS2 header (writes to file, no root or device-mapper needed).
# --align-payload=32768 forces payload at sector 32768 = 16 MiB from header start.
cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha256 \
    --pbkdf argon2id \
    --pbkdf-memory 65536 \
    --pbkdf-parallel 1 \
    --pbkdf-time-ms 2000 \
    --sector-size 512 \
    --align-payload 32768 \
    --volume-key-file "$TMPDIR/volkey.bin" \
    --key-file "$TMPDIR/passphrase.bin" \
    --batch-mode \
    "$TMPDIR/luks-container.bin"

shred -u "$TMPDIR/passphrase.bin"

# Get actual payload offset (in bytes) from the LUKS header.
PAYLOAD_BYTES=$(cryptsetup luksDump "$TMPDIR/luks-container.bin" 2>/dev/null | \
    awk '/Data segments:/{found=1} found && /offset:/{gsub(/[^0-9]/,"",$2); print $2; exit}')
[ -n "$PAYLOAD_BYTES" ] || PAYLOAD_BYTES=$(( LUKS_PAYLOAD_MIB * 1024 * 1024 ))
echo "    LUKS2 payload offset: ${PAYLOAD_BYTES} bytes ($(( PAYLOAD_BYTES / 1024 / 1024 )) MiB)"

# ── Encrypt root.ext4 into the LUKS container ─────────────────────────────────
echo "==> Encrypting root partition (this may take a while) …"
"$XTS_ENC" "$TMPDIR/volkey.bin" "$TMPDIR/luks-container.bin" \
    "$PAYLOAD_BYTES" < "$TMPDIR/root.ext4"
shred -u "$TMPDIR/volkey.bin"
echo "    done."

# ── Assemble final userdata.img ───────────────────────────────────────────────
echo "==> Assembling userdata image …"
LUKS_SIZE=$(wc -c < "$TMPDIR/luks-container.bin")
TOTAL_MIB=$(( BOOT_MIB + (LUKS_SIZE + 1024*1024 - 1) / (1024*1024) ))

dd if=/dev/zero of="$TMPDIR/userdata.img" bs=1M count="$TOTAL_MIB" 2>/dev/null
# Plain boot area at byte 0.
dd if="$TMPDIR/boot.ext4" of="$TMPDIR/userdata.img" \
    bs=512 seek=0 conv=notrunc 2>/dev/null
# LUKS container immediately after boot area.
dd if="$TMPDIR/luks-container.bin" of="$TMPDIR/userdata.img" \
    bs=512 seek="$BOOT_SECTORS" conv=notrunc 2>/dev/null

echo "    userdata.img: ${TOTAL_MIB} MiB"
echo "    boot area:    ${BOOT_MIB} MiB (plain ext4 'guixboot')"
echo "    LUKS area:    $(( TOTAL_MIB - BOOT_MIB )) MiB"

# ── Flash ─────────────────────────────────────────────────────────────────────
echo ""
echo "==> Ready to flash.  Device must be in fastboot mode."
echo "    boot.img:    $TMPDIR/boot.img"
echo "    userdata.img $TMPDIR/userdata.img"
echo ""
read -r -p "Flash now? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "==> Erasing dtbo_a …"
fastboot erase dtbo_a

echo "==> Flashing U-Boot to boot_a …"
fastboot flash boot_a "$TMPDIR/boot.img"

echo "==> Disabling vbmeta verification …"
printf '\x41\x56\x42\x30\x00\x00\x01\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00' | \
    dd bs=4096 count=1 conv=sync 2>/dev/null > "$TMPDIR/vbmeta.img"
fastboot flash vbmeta_a "$TMPDIR/vbmeta.img"

echo "==> Flashing userdata …"
fastboot flash userdata "$TMPDIR/userdata.img"

echo "==> Setting active slot to A …"
fastboot set_active a

echo "==> Rebooting …"
fastboot reboot

echo ""
echo "Done."
echo "First boot: enter the encryption passphrase when prompted by the initrd."
echo "SSH (after boot): ssh user@172.16.42.1  (password: 123456 — change it!)"
