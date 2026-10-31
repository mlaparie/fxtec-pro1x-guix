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

```sh
guix shell -m manifest.scm -- bash scripts/flash.sh systems/mobile.scm
```

Writes `boot_a/b`, `vbmeta_a/b` and `userdata`, erases `dtbo`, sets slot
a.  Makes `~/.ssh/pro1x-guix` on the PC if missing (the deploy key).

From a ready-made image (CI artifact, or a release's `rootfs.img.zst`
unpacked with `zstd -d rootfs.img.zst`):

```sh
bash scripts/flash.sh --uboot u-boot-nodtb.bin --rootfs rootfs.img
```

## 4. First boot

The root file system grows to the partition, then tuigreet.  User `user`, password `123456`: change it with `passwd`.

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

Next: [configure.md](configure.md).
