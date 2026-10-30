# Channels and updates

## Why guix and nonguix are pinned

This channel's packages (kernel, U-Boot, Phosh, ModemManager, libqmi, ...)
have no substitute server.  They are built from the exact guix and
nonguix commits you use: change those, and the next update rebuilds the
kernel and Phosh, for hours on the PC under QEMU, longer on the phone.  So
the phone follows the commits the port was built and tested with.  They
move with the port's releases.

Guix's own packages still come as substitutes for aarch64 from the Guix
build farms, for the pinned commit.

## The channel files

| file | used by | holds |
|---|---|---|
| `/etc/guix/channels.scm` | the phone, as shipped | guix and nonguix pinned, fxtec-pro1x on `main` |
| `~/.config/guix/channels.scm` | `guix pull` on the phone, and `scripts/deploy.sh` | your copy of the above, with your channels added |
| `channels.scm` (repository) | anyone, `guix pull -C channels.scm` | the same as `/etc/guix/channels.scm` |
| `channels-lock.scm` (repository) | local builds of the port | the same pins |
| `channels-ci.scm` (repository) | CI | guix and nonguix only; CI takes fxtec-pro1x from the checkout |

All pin the same guix and nonguix commits.

## Adding a channel

Add it to `~/.config/guix/channels.scm`.  Pin it (`(commit "...")`) when
you want the build to be repeatable, or when the channel follows a newer
guix than the pin: an unpinned channel may stop building against the
pinned guix.  Tailscale, pinned, is shown in [configure.md](configure.md).

## Updating

| what | how |
|---|---|
| your configuration (packages, services) | edit `config.scm`, then `scripts/deploy.sh` from the PC ([update.md](update.md)) |
| the port's fixes | `git pull` in your checkout, then `scripts/deploy.sh`: it builds with the checkout's `modules/` in front of the channel |
| guix and nonguix | with a port release, which moves the pins in `/etc/guix/channels.scm`; copy the new pins into yours |
| a user's own packages | `guix install <package>` on the phone (substitutes for Guix packages) |

`guix pull` on the phone updates only what `guix install` and on-phone
reconfigures see; it does not change the running system.

## Compared with Guix on a desktop

- **Pinned guix**: no daily `guix pull` to the newest commit (see above).
- **The PC builds**: deploys build your phone's configuration on the PC;
  reconfiguring on the phone works but is slow.
- **No systemd, no logind**: Shepherd services (`herd`), seatd for the
  sessions, polkit rules instead of logind sessions.  No `journalctl`:
  logs are in `/var/log` ([troubleshoot.md](troubleshoot.md)).
- **Boot**: U-Boot with an extlinux menu (volume-down at power-on), not
  GRUB.
- **Nonfree firmware** from nonguix and the phone's own blobs.
