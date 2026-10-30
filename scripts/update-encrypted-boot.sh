#!/usr/bin/env bash
# scripts/update-encrypted-boot.sh — update the plain boot area after reconfigure
#
# Run on the Pro1X after `guix system reconfigure` on an encrypted system.
# The plain ext4 at the start of /dev/disk/by-partlabel/userdata (mounted at
# /boot with label "guixboot") holds the kernel, initrd, and extlinux.conf
# that U-Boot reads.  Since the Guix-generated extlinux.conf references store
# paths on the encrypted root, this script copies the current kernel and initrd
# to fixed paths (/boot/vmlinuz, /boot/initrd.img) and writes a simple
# extlinux.conf that U-Boot can follow without needing to decrypt.
#
# Usage (on the device, as root or via sudo):
#   bash /run/current-system/profile/bin/update-encrypted-boot
#   # or from the repo:
#   bash scripts/update-encrypted-boot.sh

set -euo pipefail

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# /boot must be mounted (it's listed in the system's file-systems).
mountpoint -q /boot 2>/dev/null || die "/boot is not mounted"

SYSTEM=/run/current-system

# ── Find kernel binary ────────────────────────────────────────────────────────
KERNEL_PROF=$(readlink -f "$SYSTEM/kernel")
KERNEL_BIN=""
for name in Image Image.gz bzImage; do
    if [ -f "$KERNEL_PROF/$name" ]; then
        KERNEL_BIN="$KERNEL_PROF/$name"
        break
    fi
done
[ -n "$KERNEL_BIN" ] || die "cannot find kernel binary under $KERNEL_PROF"

# ── Find initrd ───────────────────────────────────────────────────────────────
INITRD=$(readlink -f "$SYSTEM/initrd")
[ -f "$INITRD" ] || die "cannot find initrd at $INITRD"

# ── Get kernel arguments from current boot parameters ────────────────────────
# The boot-parameters file stores the kernel arguments used by the running system.
PARAMS_FILE="$SYSTEM/parameters"
APPEND_LINE=""
if [ -f "$PARAMS_FILE" ]; then
    # Extract kernel-arguments from the parameters s-expression.
    APPEND_LINE=$(guile -c "
(use-modules (ice-9 rdelim))
(let* ((p (open-input-file \"$PARAMS_FILE\"))
       (params (read p)))
  (let loop ((lst params))
    (cond
     ((null? lst) #f)
     ((and (pair? (car lst)) (eq? (caar lst) 'kernel-arguments))
      (display (string-join (cdar lst) \" \")) (newline))
     (else (loop (cdr lst))))))" 2>/dev/null || true)
fi

if [ -z "$APPEND_LINE" ]; then
    APPEND_LINE="console=tty1 loglevel=4 \
g_cdc.host_addr=02:50:31:e8:00:01 g_cdc.dev_addr=02:50:31:e8:00:02"
fi

# ── Copy kernel and initrd ────────────────────────────────────────────────────
info "Copying kernel: $(basename "$KERNEL_BIN") → /boot/vmlinuz"
cp -f "$KERNEL_BIN" /boot/vmlinuz

info "Copying initrd → /boot/initrd.img"
cp -f "$INITRD" /boot/initrd.img

# ── Write extlinux.conf ───────────────────────────────────────────────────────
info "Writing /boot/extlinux/extlinux.conf…"
mkdir -p /boot/extlinux
cat > /boot/extlinux/extlinux.conf << EOF
# Updated by scripts/update-encrypted-boot.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ).
TIMEOUT 30
PROMPT 1
DEFAULT guix

LABEL guix
  MENU LABEL GNU Guix
  KERNEL /vmlinuz
  INITRD /initrd.img
  APPEND $APPEND_LINE
EOF

echo ""
info "Done.  Reboot to use the new kernel."
echo "    kernel:  $KERNEL_BIN"
echo "    initrd:  $INITRD"
echo "    APPEND:  $APPEND_LINE"
