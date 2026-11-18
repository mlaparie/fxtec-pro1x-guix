> **Developer preview.**  Calls, SMS, MMS, mobile data, Wi-Fi, audio,
> cameras, sensors, GPS and suspend work; mute in calls and outgoing
> VoLTE calls do not yet.  Do not flash this on a device you depend on.

# Guix System on the F(x)tec Pro¹x (QX1050)

GNU Guix System on the F(x)tec Pro¹x (SM6115 / Snapdragon 662): a mainline
Linux kernel, mainline U-Boot and the phone's firmware, with Sway or Phosh,
packaged as a Guix channel.  No Android kernel, no libhybris.  A port of
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos),
where the kernel patches, firmware and flash approach come from.

## What works

As observed on the phone (2026-11-14, Linux 7.3).  The sessions, menus and
phone comforts: [features.md](docs/features.md).

```
Display (BOE AMOLED, 60 Hz)      Working
GPU (Adreno 610)                 Working    freedreno
Touchscreen                      Working
Auto-rotation                    Working    portrait with the keyboard closed, landscape out
Hardware keyboard                Working    Fn layer via keyd, backlight, slider switch
Volume keys                      Working
Wi-Fi                            Working
Bluetooth                        Working    pairing, audio to a speaker
USB networking                   Working    SSH to 172.16.42.1
Speaker, earpiece, microphones   Working
Headphones                       Untested
Vibration motor                  Working
Calls                            Partial    both directions, earpiece and speaker; mute has no effect yet
VoLTE                            Partial    incoming calls on 4G; outgoing ones fall back to 3G after 22-26 s
SMS, MMS                         Working    Chatty
Mobile data                      Working    3G and 4G
Rear and front cameras           Partial    photos; focus, colours and the camera app are early
Accelerometer, proximity         Working
Light sensor, gyroscope          Working
Battery                          Working
Screen dimming, blank, lock      Working    configurable
Double tap to wake               Working
Fingerprint reader               Working    unlocks the lock screen
Android apps (Waydroid)          Working    with or without Google Play
Suspend                          Working    calls and SMS wake it
GPS                              Working    Satellite app; not yet passed to Android apps
Video encoding (Venus)           Working    hardware H.264 for screen streaming
Video decoding (Venus)           Untested
NFC                              Untested
Full-disk encryption             Working    LUKS2, passphrase at boot
```

## Install

Flashing **erases userdata** and replaces the bootloader on slot A.  You
need an unlocked Pro¹x, a PC with Guix (or the release images) and a USB
cable.

1. Back up the modem and boot partitions, from Android with ADB root:
   `bash scripts/backup-stock.sh`.
2. Unlock the bootloader: `fastboot flashing unlock`.
3. Flash, in fastboot mode:
   `guix shell -m manifest.scm -- bash scripts/flash.sh` (add `--encrypt`
   for an encrypted root).
4. Log in as `user`, password `123456` (change it), on the phone or with
   `ssh user@172.16.42.1`.

Each [GitHub release](https://github.com/mlaparie/fxtec-pro1x-guix/releases)
has ready-made images for those without Guix.  Step by step, reflashing a
phone in use, and the images: [install.md](docs/install.md).  Updating
afterwards: [update.md](docs/update.md).

## Documentation

| page | |
|---|---|
| [docs/features.md](docs/features.md) | what it is and what works |
| [docs/install.md](docs/install.md) | flashing the first time; reflashing with a backup of your data |
| [docs/usage.md](docs/usage.md) | daily use: sessions, keyboard, swipes and menus, screen, network, passwords |
| [docs/configure.md](docs/configure.md) | your config.scm and channels, the port's options |
| [docs/home.md](docs/home.md) | home files: managed, seeded once, or left alone (Guix Home) |
| [docs/update.md](docs/update.md) | updating, generations, rollback |
| [docs/channels.md](docs/channels.md) | why pins, the channel files, adding channels, Guix on a phone vs a desktop |
| [docs/troubleshoot.md](docs/troubleshoot.md) | logs, known problems, recovery |
| [docs/develop.md](docs/develop.md) | working on the port: layout, building, deploying, services, encryption, other distributions |
| [NEWS.md](NEWS.md), [TODO.org](TODO.org) | release notes; the port's state and tasks |

Source on sr.ht (`~mlaparie/fxtec-pro1x-guix`), mirrored on
[GitHub](https://github.com/mlaparie/fxtec-pro1x-guix), where CI builds the
images.

## Credits

Kernel, firmware and patches from
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos);
kernel source from [sm6115-mainline](https://github.com/sm6115-mainline);
many fixes from moWerk's
[SailfishOS mainline port](https://github.com/moWerk/sailfishos-pro1x-mainline).
Boot image parameters from macneisj's build script and the
[postmarketOS port](https://wiki.postmarketos.org/wiki/F(x)tec_Pro1_X_(fxtec-pro1x)).
