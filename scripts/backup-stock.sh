#!/usr/bin/env bash
# scripts/backup-stock.sh — back up critical Pro1X partitions before flashing
#
# Run this BEFORE unlocking the bootloader or flashing anything.
# Bootloader unlock wipes userdata; do it AFTER this backup.
#
# Usage:
#   bash scripts/backup-stock.sh [output-dir]
#
# Requires: adb (android-tools), device booted into Android with USB debugging on.
#
# Root access: the script tries `adb root` first (works on eng/userdebug builds or
# if the bootloader is already unlocked).  If that fails it falls back to `su -c`
# via a root app (Magisk etc.).  If neither is available, see EDL section at the
# bottom of this file.
#
# What gets backed up:
#   modemst1 / modemst2  — modem EFS: IMEI, RF calibration  [CRITICAL]
#   fsg / fsc            — EFS failsafe golden/copy          [CRITICAL]
#   persist              — Wi-Fi MAC, BT MAC, sensor cal     [important]
#   boot_a / boot_b      — original Android boot images      [nice to have]
#   vbmeta_a / vbmeta_b  — AVB metadata                     [nice to have]
#   dtbo_a               — Android device-tree overlay       [nice to have]
#
# Partition layout note: on UFS (block) devices Qualcomm exposes partitions at
# /dev/block/bootdevice/by-name/<name>.  The script probes both that path and
# /dev/block/by-name/ in case the symlink location differs.

set -euo pipefail

OUTDIR="${1:-backup-$(date +%Y%m%d-%H%M%S)}"
BY_NAME="/dev/block/bootdevice/by-name"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "    [warn] $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found (install android-tools)"; }
need adb

# ── Check device is reachable ─────────────────────────────────────────────────
info "Waiting for ADB device…"
adb wait-for-device
SERIAL=$(adb get-serialno)
info "Found device: $SERIAL"

mkdir -p "$OUTDIR"
info "Saving backups to: $OUTDIR/"

# ── Gain root ─────────────────────────────────────────────────────────────────
ROOT_CMD=""
if adb root 2>&1 | grep -q "restarting adbd as root"; then
    sleep 1
    ROOT_CMD=""          # adb shell already runs as root
    info "ADB root: OK"
elif adb shell "id" 2>/dev/null | grep -q "uid=0"; then
    ROOT_CMD=""
    info "ADB already running as root"
else
    # Try su -c (Magisk or similar)
    if adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
        ROOT_CMD="su -c"
        info "Root via su: OK"
    else
        warn "No root access available via 'adb root' or 'su'."
        warn "Partition dumps will fail unless you grant root in a root manager app."
        warn "See EDL fallback instructions at the bottom of this script."
        ROOT_CMD="NOROOT"
    fi
fi

# ── Probe partition path ───────────────────────────────────────────────────────
if adb shell "[ -d $BY_NAME ]" 2>/dev/null; then
    PARTDIR="$BY_NAME"
elif adb shell "[ -d /dev/block/by-name ]" 2>/dev/null; then
    PARTDIR="/dev/block/by-name"
else
    die "Cannot find partition directory on device (tried $BY_NAME and /dev/block/by-name)"
fi
info "Partition dir: $PARTDIR"

# ── Dump one partition ─────────────────────────────────────────────────────────
dump_part() {
    local name="$1"
    local out="$OUTDIR/${name}.img"

    if [ "$ROOT_CMD" = "NOROOT" ]; then
        warn "Skipping $name (no root)"
        return
    fi

    printf "    %-16s" "$name"
    if ! adb shell "$ROOT_CMD ls $PARTDIR/$name" >/dev/null 2>&1; then
        echo " [not found — skipping]"
        return
    fi

    if [ -n "$ROOT_CMD" ]; then
        adb exec-out "$ROOT_CMD dd if=$PARTDIR/$name" > "$out" 2>/dev/null
    else
        adb exec-out "dd if=$PARTDIR/$name" > "$out" 2>/dev/null
    fi

    local sz
    sz=$(wc -c < "$out")
    printf " %d KiB → %s\n" "$(( sz / 1024 ))" "$out"
}

# ── Critical partitions (IMEI / EFS / calibration) ────────────────────────────
info "Backing up critical partitions…"
dump_part modemst1
dump_part modemst2
dump_part fsg
dump_part fsc
dump_part persist

# ── Bootloader / AVB (useful for Android restore) ─────────────────────────────
info "Backing up bootloader and AVB partitions…"
dump_part boot_a
dump_part boot_b
dump_part vbmeta_a
dump_part vbmeta_b
dump_part dtbo_a

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "Backup complete.  Contents of $OUTDIR/:"
ls -lh "$OUTDIR/"
echo ""
echo "Keep this directory somewhere safe (NOT on the device)."
echo "To restore the modem EFS after flashing:"
echo "  fastboot flash modemst1 $OUTDIR/modemst1.img"
echo "  fastboot flash modemst2 $OUTDIR/modemst2.img"
echo "  fastboot flash fsg      $OUTDIR/fsg.img"
echo "  fastboot flash fsc      $OUTDIR/fsc.img"
echo "  fastboot flash persist  $OUTDIR/persist.img"

# ── EDL fallback (manual, no firehose included) ───────────────────────────────
cat <<'EDL'

────────────────────────────────────────────────────────────────────────────────
EDL FALLBACK (if ADB root not available)
────────────────────────────────────────────────────────────────────────────────
EDL (Emergency Download, Qualcomm 9008 mode) can back up every partition even
with a locked bootloader, but requires the device-specific firehose programmer
binary — a Qualcomm proprietary ELF not included in this repo.

How to get the firehose programmer for the Pro1X (SM6115):
  • Extract from an official F(x)tec factory image or Fastboot ROM if F(x)tec
    ever released one.  The file is typically named:
      prog_firehose_ddr_sm6115.elf
    and is found inside the firmware archive alongside .img partition images.
  • Some devices store a copy in the 'abl_a' partition itself; dumping abl_a
    via fastboot (after unlock) and inspecting it may yield the programmer.
  • Community sources (ThunderSoft, Qualcomm QPST packages) sometimes host
    SM6115 programmers — verify sha256 before use.

Once you have the programmer:
  1. Enter EDL on the Pro1X: power off, hold Vol-Down + Vol-Up, plug USB.
     Or from a root shell: adb shell "su -c 'echo edl > /sys/power/reboot_cmd'"
  2. Install qdl (linux-msm/qdl on GitHub).
  3. Run:
       qdl --storage ufs prog_firehose_ddr_sm6115.elf
     then use the firehose XML protocol to read partitions.
  4. Or use bkerler/edl (Python, more user-friendly):
       pip install edl
       edl rl backup-edl/   # reads all partitions to a directory

Without EDL: if you lose modemst1/2, it is recoverable if F(x)tec can provide
a factory EFS backup tied to your device's IMEI, or if you have an identical
unit to clone from.  The IMEI can also be written back via AT commands if you
know it.
EDL
