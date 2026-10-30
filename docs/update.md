# Updating

## From the PC (recommended)

```sh
bash scripts/deploy.sh                  # phone on USB, 172.16.42.1
bash scripts/deploy.sh <host>           # e.g. its Tailscale name
```

Builds on the PC what a reconfigure on the phone would build: it copies
the phone's `~/.config/guix/config.scm` and `channels.scm` (or
`/etc/guix`'s), builds with those channels, installs over SSH as root and
activates the result.  Your `config.scm` is kept.

`bash scripts/deploy.sh --repo [systems/mobile.scm]` deploys a system file
from the repository instead, replacing the phone's configuration (for
work on the port).

## On the phone

```sh
guix pull                                # then log out and in once
sudo guix system reconfigure ~/.config/guix/config.scm
```

Builds on the phone: hours if the kernel or Phosh changed.

## After an update

- Kernel, initrd or firmware changed: reboot.
- New session changes (Phosh, Sway): log out and in.
- A service that was running keeps its old version until restarted:
  `sudo herd restart <service>` or reboot.

## Generations and rollback

Each update is a generation; the boot menu keeps the latest ones.

```sh
guix system list-generations
sudo guix system roll-back               # previous one; reboot to run it
sudo guix system switch-generation 12
```

If the phone does not boot far enough for SSH: hold **volume-down** at
power-on and pick an older entry in the U-Boot menu.

Do not delete all old generations: they are the only rollback.
