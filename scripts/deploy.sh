#!/usr/bin/env bash
# scripts/deploy.sh — update the phone over USB Ethernet without reflashing
#
# Usage:
#   bash scripts/deploy.sh [host]                    the phone's own configuration
#   bash scripts/deploy.sh --repo [system-file] [host]   a system from this tree
#   defaults: host 172.16.42.1, system-file systems/mobile.scm
#
# By default it builds what `sudo guix system reconfigure
# ~/.config/guix/config.scm' would build on the phone, with the phone's
# own channels, but on this host's CPU: it copies the phone user's
# ~/.config/guix/config.scm and channels.scm (or /etc/guix's when the user
# has none) and their ~/.ssh/*.pub (for relative key paths), and runs
# guix deploy under `guix time-machine -C <the phone's channels.scm>'.
# Changes the owner made in config.scm are kept.  -L modules puts this
# tree's modules in front of the fxtec-pro1x channel's, so unpushed work on
# the port is tested on top of the owner's configuration.
#
# --repo deploys a system file from this tree with this host's guix
# instead (the old behaviour): it replaces the phone's configuration.
#
# guix deploy (deploy/pro1x.scm) copies the closure as root over SSH and
# activates it as a new generation, like guix system reconfigure.  Kernel,
# initrd and firmware changes need a reboot.  Older generations stay in the
# U-Boot menu (hold volume-down).  It needs root SSH by the key
# scripts/flash.sh made, ~/.ssh/pro1x-guix, and keeps that key in root's
# authorized keys, whatever the configuration says.
#
# Environment: PRO1X_USER, the phone account whose configuration is used
# (default user).
#
# After a reflash the phone has a new SSH host key and guix deploy stops
# with "known-changed".  Refresh it (USB link to your own phone):
#   ssh-keygen -R 172.16.42.1
#   ssh-keyscan -t ed25519 172.16.42.1 >> ~/.ssh/known_hosts
#
# State: --repo used since 2026-10-28.  The phone-configuration mode is
# new (2026-10-30), not yet run.  For systems/mobile-encrypted.scm, also
# run scripts/update-encrypted-boot.sh on the phone afterwards.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--repo" ]]; then
    shift
    PRO1X_SYSTEM="${1:-systems/mobile.scm}" \
    PRO1X_HOST="${2:-172.16.42.1}" \
        guix deploy -L modules deploy/pro1x.scm
    echo "Deployed.  Reboot the phone if the kernel, initrd or firmware changed."
    exit 0
fi

host="${1:-172.16.42.1}"
user="${PRO1X_USER:-user}"
ssh_root=(ssh -i "$HOME/.ssh/pro1x-guix" -o BatchMode=yes "root@$host")

# The phone's configuration, in a tree with the same layout, so paths
# relative to config.scm (../../.ssh/...) resolve as on the phone.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="/home/$user"
if "${ssh_root[@]}" test -f "$home/.config/guix/config.scm"; then
    dir="$home/.config/guix"
else
    dir=/etc/guix
    echo "No $home/.config/guix/config.scm on the phone: using /etc/guix's." >&2
fi
mkdir -p "$tmp$dir" "$tmp$home/.ssh"
"${ssh_root[@]}" cat "$dir/config.scm" > "$tmp$dir/config.scm"
if "${ssh_root[@]}" test -f "$dir/channels.scm"; then
    "${ssh_root[@]}" cat "$dir/channels.scm" > "$tmp$dir/channels.scm"
else
    "${ssh_root[@]}" cat /etc/guix/channels.scm > "$tmp$dir/channels.scm"
fi
"${ssh_root[@]}" "cd $home/.ssh 2>/dev/null && tar cf - *.pub 2>/dev/null" \
    | tar xf - -C "$tmp$home/.ssh" 2>/dev/null || true

echo "Configuration: $dir/config.scm, channels: $dir/channels.scm (phone)"
PRO1X_SYSTEM="$tmp$dir/config.scm" \
PRO1X_HOST="$host" \
PRO1X_PHONE_CHANNELS=1 \
    guix time-machine -C "$tmp$dir/channels.scm" -- \
    deploy -L "$PWD/modules" deploy/pro1x.scm

echo "Deployed.  Reboot the phone if the kernel, initrd or firmware changed."
