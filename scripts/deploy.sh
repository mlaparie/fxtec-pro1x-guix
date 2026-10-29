#!/usr/bin/env bash
# scripts/deploy.sh — update the phone over USB Ethernet without reflashing
#
# Usage:
#   bash scripts/deploy.sh [system-file] [host]
#   defaults: systems/mobile.scm 172.16.42.1
#
# Runs guix deploy with deploy/pro1x.scm: builds on this host (same guix as
# scripts/flash.sh, so unchanged store items are not copied again), copies
# the closure as root over SSH, and activates it as a new generation, like
# guix system reconfigure.  Kernel, initrd and firmware changes need a
# reboot.  Older generations stay in the U-Boot menu (hold volume-down).
# Needs root SSH by the key scripts/flash.sh made, ~/.ssh/pro1x-guix: on in
# the system as flashed; in a configuration made from /etc/guix/config.scm
# only if its #:root-ssh-keys line is uncommented.  It deploys
# systems/mobile.scm, the port's system, replacing such a configuration.
#
# After a reflash the phone has a new SSH host key and guix deploy stops
# with "known-changed".  Refresh it (USB link to your own phone):
#   ssh-keygen -R 172.16.42.1
#   ssh-keyscan -t ed25519 172.16.42.1 >> ~/.ssh/known_hosts
#
# State: first used 2026-10-28.  For systems/mobile-encrypted.scm, also run
# scripts/update-encrypted-boot.sh on the phone afterwards.

set -euo pipefail

cd "$(dirname "$0")/.."

PRO1X_SYSTEM="${1:-systems/mobile.scm}" \
PRO1X_HOST="${2:-172.16.42.1}" \
    guix deploy -L modules deploy/pro1x.scm

echo "Deployed.  Reboot the phone if the kernel, initrd or firmware changed."
