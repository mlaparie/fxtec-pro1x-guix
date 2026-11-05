#!/usr/bin/env bash
# scripts/backup-phone.sh — save the phone's data to the PC, and put it back
# after a reflash
#
# Usage:
#   bash scripts/backup-phone.sh backup  [-o FILE] [HOST]
#   bash scripts/backup-phone.sh restore FILE [HOST]
#   defaults: HOST 172.16.42.1 (USB), FILE ~/pro1x-backup-YYYY-MM-DD.tar
#
# What is saved (one tar, readable only by you):
#   /home/USER                 everything but .cache and the flatpak apps; the
#                              list of flatpak apps goes in flatpak-apps.txt
#   /var/lib/NetworkManager    and /etc/NetworkManager/system-connections:
#                              Wi-Fi networks with their passwords, APNs
#   /var/lib/bluetooth         pairings
#   /var/lib/tailscale         the node's identity (no new login)
#   /var/lib/pro1x             the port's state (charge limit, CPU mode…)
#   /etc/ssh                   host keys (the PC keeps trusting the phone)
#                              and root's authorized keys
# Not saved: /etc/shadow (passwords: set them again with passwd), the store
# (the system comes back with a deploy), generations.
#
# The archive holds Wi-Fi passwords and private keys: keep it off git and
# off shared disks.
#
# Close the browser first: a running LibreWolf or Firefox writes its profile
# while tar reads it, and the copy can come back broken.  The script refuses
# while one runs (PRO1X_FORCE=1 to go on).
#
# Restore is for a freshly flashed phone, before using it: it writes over the
# same paths.  Then deploy (scripts/deploy.sh: the restored config.scm),
# reinstall the flatpak apps (printed at the end), and log out and in, or
# reboot.
#
# Logs in as root with the deploy key (~/.ssh/pro1x-guix).  An image from CI
# has no root key: for the restore, PRO1X_LOGIN=user logs in as the user
# (password) and uses sudo (asks for it again).  After the restore the phone
# has its old SSH host key back, the one ~/.ssh/known_hosts had before the
# reflash: ssh then trusts it again, and the restore's own login (with the
# new key) needs a separate known_hosts entry, or `ssh-keygen -R HOST` first.
#
# Environment: PRO1X_USER (default user), PRO1X_LOGIN (default root),
# PRO1X_FORCE.
#
# State: the same commands, by hand, backed up and restored the author's
# phone across the first encrypted flash (2026-11-05).  The script's backup
# run on the phone (2026-11-06); its restore not yet.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

user="${PRO1X_USER:-user}"
login="${PRO1X_LOGIN:-root}"
paths=(home/"$user" var/lib/NetworkManager etc/NetworkManager/system-connections
       var/lib/bluetooth var/lib/tailscale var/lib/pro1x etc/ssh)

phone() {                       # phone COMMAND: as root, with the deploy key
    ssh -i "$HOME/.ssh/pro1x-guix" -o IdentitiesOnly=yes "root@$host" "$1"
}

phone_sudo() {                  # phone_sudo COMMAND: as root, or through sudo
    if [[ "$login" == root ]]; then
        phone "$1"
    else                        # sudo asks on the terminal; the command comes in
        ssh -t "$login@$host" \
            "echo $(printf '%s' "$1" | base64 -w0) | base64 -d | sudo sh"
    fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
    backup)
        out="$HOME/pro1x-backup-$(date +%F).tar"
        if [[ "${1:-}" == -o ]]; then out="$2"; shift 2; fi
        host="${1:-172.16.42.1}"
        [[ -e "$out" ]] && die "$out exists; not overwriting it"
        # Names, not a pattern: pgrep matches at most 15 characters of it.
        if [[ -z "${PRO1X_FORCE:-}" ]] &&
           phone "r=1; for n in librewolf .librewolf-real firefox .firefox-real; do
                      pgrep -x -u $user -l \$n && r=0; done; exit \$r"; then
            die "close the browser on the phone first (PRO1X_FORCE=1 to go on)"
        fi
        umask 077
        echo "==> Saving the phone's data to $out…"
        # As the user: run as root, flatpak made root-owned files in the
        # user's repository, and the reinstall then failed (2026-11-06).
        phone "su - $user -c 'flatpak --user list --app --columns=application \
                   > ~/flatpak-apps.txt 2>/dev/null' || true
               ok=; for p in ${paths[*]}; do [ -e /\$p ] && ok=\"\$ok \$p\"; done
               tar -C / --exclude=home/$user/.cache \
                   --exclude=home/$user/.local/share/flatpak -cf - \$ok" > "$out"
        list=$(tar -tf "$out")
        echo "    $(wc -l <<< "$list") entries, $(du -h "$out" | cut -f1)."
        for p in home/"$user"/.config etc/ssh; do
            grep -q "^$p/" <<< "$list" || echo "    [warn] nothing under $p" >&2
        done
        echo "Done.  Keep $out private: it holds Wi-Fi passwords and keys." ;;
    restore)
        in="${1:?usage: backup-phone.sh restore FILE [HOST]}"
        host="${2:-172.16.42.1}"
        [[ -r "$in" ]] || die "cannot read $in"
        tar -tf "$in" >/dev/null || die "$in is not a readable tar"
        echo "==> Copying $in to the phone…"
        tmp=/tmp/pro1x-restore.tar
        if [[ "$login" == root ]]; then
            scp -i "$HOME/.ssh/pro1x-guix" -o IdentitiesOnly=yes "$in" "root@$host:$tmp"
        else
            scp "$in" "$login@$host:$tmp"
        fi
        echo "==> Unpacking it over /…"
        phone_sudo "chmod 600 $tmp; tar -C / --same-owner -xpf $tmp; s=\$?; \
                  shred -u $tmp; nmcli connection reload 2>/dev/null; exit \$s"
        cat <<EOF
Done.  Next:
  1. bash scripts/deploy.sh $host     (the restored config.scm)
  2. on the phone, the flatpak apps:
       flatpak remote-add --user --if-not-exists flathub \\
           https://dl.flathub.org/repo/flathub.flatpakrepo
       xargs -r flatpak install --user -y flathub < ~/flatpak-apps.txt
  3. passwd                            (the password is still the default)
  4. log out and in, or reboot
EOF
        ;;
    *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
