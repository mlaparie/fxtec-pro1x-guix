# Installing

Flashing **erases userdata** and replaces the bootloader on slot A.

## You need

- the Pro¹x, bootloader unlocked;
- a PC with GNU Guix and [nonguix](https://gitlab.com/nonguix/nonguix),
  building for aarch64 (native, or QEMU binfmt; the first build takes
  hours under QEMU; a CI image skips it);
- a USB cable.

## 1. Back up, from Android with ADB root

```sh
bash scripts/backup-stock.sh        # backup-YYYYMMDD-HHMMSS/
```

Saves `modemst1`, `modemst2`, `fsg`, `fsc`, `persist` and the boot
images: per-unit data (calibration, IMEI) that cannot be recreated.
Keep it off the phone and out of git.

## 2. Unlock (erases userdata)

```sh
fastboot flashing unlock
```

## 3. Flash, in fastboot mode

Fastboot mode is the stock bootloader's: power off, then hold volume-down
and press power, keeping volume-down held until the fastboot screen.  Once
this port is installed, U-Boot's menu has a fastboot entry too: not that
one, it cannot write these partitions (`fastboot getvar
version-bootloader` names U-Boot there).  From a running system, `sudo
reboot` cannot pass the reason; the stock fastboot screen is reached with
the keys.

```sh
guix shell -m manifest.scm -- bash scripts/flash.sh systems/mobile.scm
```

Writes `boot_a/b`, `vbmeta_a/b` and `userdata`, erases `dtbo`, sets slot
a.  Makes `~/.ssh/pro1x-guix` on the PC if missing (the deploy key).

From a ready-made image (a CI build's `rootfs-mobile` artifact, or a
release's `rootfs.img.zst.part*`, joined with `cat rootfs.img.zst.part* |
zstd -d -o rootfs.img`):

```sh
bash scripts/flash.sh --uboot u-boot-nodtb.bin --rootfs rootfs.img
```

With `--encrypt` (or "yes" when it asks), the root is encrypted (LUKS2):
the script asks for the passphrase, and the phone asks for it at each
boot ([README](../README.md#full-disk-encryption-luks2)).

## 4. First boot

The root file system grows to the partition (about 20 s, once), then
tuigreet.  User `user`, password `123456`: change it with `passwd`
([usage.md](usage.md#passwords)).

## 5. Connect

```sh
ssh user@172.16.42.1                # over the USB cable
```

Ready-made images do not let your deploy key in as root; add it once:

```sh
ssh user@172.16.42.1 "sudo mkdir -p /root/.ssh && \
  sudo tee -a /root/.ssh/authorized_keys" < ~/.ssh/pro1x-guix.pub
```

After a reflash the host key changes:

```sh
ssh-keygen -R 172.16.42.1
ssh-keyscan -t ed25519 172.16.42.1 >> ~/.ssh/known_hosts
```

## Reflashing a phone in use

A flash erases userdata: home, Wi-Fi networks, pairings, every generation.
Save them to the PC first, and put them back on the new system:

```sh
bash scripts/backup-phone.sh backup            # ~/pro1x-backup-YYYY-MM-DD.tar
# … flash …
bash scripts/backup-phone.sh restore ~/pro1x-backup-YYYY-MM-DD.tar
bash scripts/deploy.sh                         # the restored config.scm
```

Close the browser on the phone before the backup (the script refuses
while one runs).  The archive holds Wi-Fi passwords and the phone's SSH
keys: keep it private.  It has no passwords: set yours again with
`passwd`.  Flatpak apps are listed, not saved; the restore prints the two
commands that reinstall them.  After a ready-made image, which has no
root key, restore with `PRO1X_LOGIN=user bash scripts/backup-phone.sh
restore …` (asks for the user's password and sudo's).  The restore gives
the phone its old SSH host key back.

Next: [configure.md](configure.md).
