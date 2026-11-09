#!/usr/bin/env bash
# scripts/deploy.sh — update the phone over USB Ethernet without reflashing
#
# Usage:
#   bash scripts/deploy.sh [--system] [--home] [host]   the phone's own configuration
#   bash scripts/deploy.sh --repo [system-file] [host]  a system from this tree
#   bash scripts/deploy.sh --help                       this text
#   defaults: --system, host 172.16.42.1, system-file systems/mobile.scm
#
# --system deploys ~/.config/guix/config.scm and --home ~/.config/guix/home.scm.
# With both, the system goes first.  They are separate: a system deploy leaves
# the home alone.  On the phone, the same home is
# `guix home reconfigure ~/.config/guix/home.scm'.
#
# --home builds home.scm for aarch64 on this host with the phone's channels,
# copies what the phone lacks as root over SSH, then makes it a new generation
# and activates it as the phone's user, like guix home reconfigure.
#
# --system builds what `sudo guix system reconfigure
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
# The channel's commit comes from sr.ht, or from the GitHub mirror when sr.ht
# does not answer.
#
# Environment: PRO1X_USER, the phone account whose configuration is used
# (default user).  PRO1X_GUIX_FLAGS, extra options for guix deploy and guix
# build, such as --fallback.
#
# After a reflash the phone has a new SSH host key and guix deploy stops
# with "known-changed".  Refresh it (USB link to your own phone):
#   ssh-keygen -R 172.16.42.1
#   ssh-keyscan -t ed25519 172.16.42.1 >> ~/.ssh/known_hosts
#
# State: --repo used since 2026-10-28.  The phone-configuration mode is
# new (2026-10-30), not yet run.  On an encrypted system, the phone's
# pro1x-boot-menu service copies the new kernel and initrd to the plain area
# once Guix has written extlinux.conf: give it some seconds before a reboot.

set -euo pipefail

cd "$(dirname "$0")/.."

# --help prints the comment at the top of this file.
usage() { sed -n '2,/^$/{/^$/d;s/^# \?//;p}' scripts/deploy.sh; }

want_system=
want_home=
while [[ "${1:-}" == -* ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --system) want_system=1 ;;
        --home) want_home=1 ;;
        --repo) break ;;
        *) echo "error: unknown option $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
done
[[ -n "$want_system$want_home" ]] || want_system=1

if [[ "${1:-}" == "--repo" ]]; then
    [[ -z "$want_home" ]] || { echo "error: --repo deploys a system, not a home" >&2; exit 1; }
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
# Not an `if': ssh's own failure (255) must stop here, not read as "no such file",
# or a phone that drops off for a moment gets the stock configuration.
status=0
"${ssh_root[@]}" test -f "$home/.config/guix/config.scm" || status=$?
[[ "$status" != 255 ]] || { echo "error: cannot reach root@$host" >&2; exit 1; }
if [[ "$status" == 0 ]]; then
    dir="$home/.config/guix"
else
    dir=/etc/guix
    echo "No $home/.config/guix/config.scm on the phone: using /etc/guix's." >&2
fi
mkdir -p "$tmp$dir" "$tmp$home/.ssh"
# The user's whole directory, so what config.scm includes or names with
# local-file (home.scm, files of a managed home) is there too; not
# current (the guix pull profile) nor backups.  /etc/guix also holds
# Guix's signing key: only its config.scm and home.scm.
if [[ "$dir" == /etc/guix ]]; then
    "${ssh_root[@]}" "cd $dir && tar cf - config.scm \
            \$(test -f home.scm && echo home.scm)" | tar xf - -C "$tmp$dir"
else
    "${ssh_root[@]}" "cd $dir && tar cf - --exclude=./current \
            --exclude='*.bak*' --exclude='*~' ." | tar xf - -C "$tmp$dir"
fi
if "${ssh_root[@]}" test -f "$dir/channels.scm"; then
    "${ssh_root[@]}" cat "$dir/channels.scm" > "$tmp$dir/channels.scm"
else
    "${ssh_root[@]}" cat /etc/guix/channels.scm > "$tmp$dir/channels.scm"
fi
"${ssh_root[@]}" "cd $home/.ssh 2>/dev/null && tar cf - *.pub 2>/dev/null" \
    | tar xf - -C "$tmp$home/.ssh" 2>/dev/null || true

# sr.ht down: this port's channel from its GitHub mirror.
srht=https://git.sr.ht/~mlaparie/fxtec-pro1x-guix
mirror=https://github.com/mlaparie/fxtec-pro1x-guix
if grep -q "$srht" "$tmp$dir/channels.scm" &&
   ! timeout 20 git ls-remote "$srht" HEAD >/dev/null 2>&1; then
    echo "sr.ht not answering: fetching the channel from $mirror." >&2
    sed -i "s|$srht|$mirror|" "$tmp$dir/channels.scm"
fi

deploy_system() {
    # The root's type, which the system must declare (deploy/pro1x.scm checks).
    local root_type
    root_type=$("${ssh_root[@]}" findmnt -no FSTYPE /) ||
        { echo "error: cannot read the phone's root type" >&2; exit 1; }

    echo "Configuration: $dir/config.scm, channels: $dir/channels.scm (phone)"
    PRO1X_ROOT_FSTYPE="$root_type" \
    PRO1X_SYSTEM="$tmp$dir/config.scm" \
    PRO1X_HOST="$host" \
    PRO1X_PHONE_CHANNELS=1 \
        guix time-machine -C "$tmp$dir/channels.scm" -- \
        deploy ${PRO1X_GUIX_FLAGS:-} -L "$PWD/modules" deploy/pro1x.scm

    echo "Deployed.  Reboot the phone if the kernel, initrd or firmware changed."
}

deploy_home() {
    [[ -f "$tmp$dir/home.scm" ]] ||
        { echo "error: no $dir/home.scm on the phone" >&2; exit 1; }

    echo "Home: $dir/home.scm, channels: $dir/channels.scm (phone)"
    local new_home missing
    new_home=$(guix time-machine -C "$tmp$dir/channels.scm" -- \
        build ${PRO1X_GUIX_FLAGS:-} --system=aarch64-linux -L "$PWD/modules" \
        -f "$tmp$dir/home.scm" | tail -1)

    # A phone's own reconfigure rewrites its ACL without this host's key.
    "${ssh_root[@]}" guix archive --authorize < /etc/guix/signing-key.pub
    missing=$(guix gc -R "$new_home" | "${ssh_root[@]}" \
        'while read -r p; do test -e "$p" || echo "$p"; done')
    if [[ -n "$missing" ]]; then
        guix archive --export $missing |
            "${ssh_root[0]}" -C "${ssh_root[@]:1}" guix archive --import
    fi

    # What guix home reconfigure does.  The login shell may be fish: use bash.
    "${ssh_root[@]}" "su -s /run/current-system/profile/bin/bash - $user -c 'bash -s'" <<EOF
set -e
cd /var/guix/profiles/per-user/$user
if [ "\$(readlink -f guix-home 2>/dev/null)" = "$new_home" ]; then
    echo "Home unchanged."
    exit 0
fi
n=\$(ls -d guix-home-*-link 2>/dev/null | sed 's/guix-home-//;s/-link//' | sort -n | tail -1)
n=\$((\${n:-0} + 1))
ln -sfn "$new_home" guix-home-\$n-link
ln -sfn guix-home-\$n-link guix-home
GUIX_NEW_HOME="$new_home" "$new_home/activate"
EOF

    echo "Home deployed: $new_home"
}

[[ -z "$want_system" ]] || deploy_system
[[ -z "$want_home" ]] || deploy_home
