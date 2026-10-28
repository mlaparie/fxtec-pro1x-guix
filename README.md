> **Work in progress — partially functional.**
> Boot, display, hardware keyboard, USB SSH, and bare sway work.
> Audio, modem, and several other features are unverified or broken.
> Do not flash this on a device you depend on.

# Guix System on the F(x)tec Pro1X (QX1050)

Mainline Linux and U-Boot for the F(x)tec Pro1X (SM6115 / Snapdragon 662),
packaged as a GNU Guix channel. Port of
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos);
kernel patches, firmware, and flash approach originate there.

> Flashing **erases userdata** and replaces the bootloader on slot A.
> Back up first (`scripts/backup-stock.sh`). Unlock the bootloader before
> doing anything.

## Port status

```
Display (BOE AMOLED, 60 Hz)      Working
GPU (Adreno 610)                 Untested
Touchscreen                      Untested
Hardware keyboard                Working    AW9523B driver, Fn layer via keyd
Keyboard backlight               Broken     not yet working
Keyboard slider switch           Untested
Wi-Fi                            Working    firmware via tqftpserv over QRTR
Bluetooth                        Untested
USB gadget (Ethernet)            Working    172.16.42.1 SSH; requires host udev/network setup
Speaker / earpiece / headphones  Untested   audio stack incomplete (see TODO §1)
Microphones                      Untested
Vibration motor                  Untested   (only verified in Phosh, not TTY)
Calls                            Untested
SMS / mobile data                Untested
Rear camera (IMX582)             Untested   libcamera-pro1x with sensor patches
Front camera (S5K4H7)            Untested
Sensors (accel, gyro, ALS, prox) Untested   ADSP via hexagonrpcd + iio-sensor-proxy
Battery / charging               Untested
Suspend                          Untested
GPS, NFC, video codecs           Untested
Full-disk encryption             Untested   systems/mobile-encrypted.scm + flash-encrypted.sh
```

## Layout

```
fxtec-pro1x/packages/        kernel, u-boot, firmware, audio, misc
fxtec-pro1x/packages/sxmo.scm  clickclack, sxmo-utils (Sxmo packages)
fxtec-pro1x/services/        Shepherd services: audio, boot, camera, fde, hardware,
                             keyboard, modem, sensors, usb-network
systems/minimal.scm          Console + SSH system (baseline)
systems/mobile.scm           Phosh + Sxmo desktop (greetd/tuigreet session picker)
systems/mobile-encrypted.scm Phosh with LUKS2 full-disk encryption
device/                      Distro-independent: kernel patches + config, UCM2 profiles,
                             libcamera patches + tuning, hexagonfs, keyd, udev rules,
                             FDE helpers (xts-encrypt.c)
scripts/backup-stock.sh      Back up modem EFS and boot partitions before flashing
scripts/flash.sh             Initial flash (plain)
scripts/flash-encrypted.sh   Initial flash with LUKS2
scripts/update-encrypted-boot.sh  Copy new kernel/initrd to plain boot after reconfigure
tools/                       On-device diagnostics (haptics-tune, cam-focus, sensors-check)
channels.scm                 Channel descriptor (unpinned)
channels-lock.scm            Pinned channel commits for reproducible local builds
channels-ci.scm              Pinned guix+nonguix for CI (fxtec-pro1x loaded via -L .)
manifest.scm                 Flash tooling: fastboot, mkbootimg, util-linux, e2fsprogs
.guix-channel                Channel descriptor for use as a Guix channel
```

## Prerequisites

- GNU Guix with the [nonguix](https://gitlab.com/nonguix/nonguix) channel (for `linux-firmware`).
- aarch64 build support: native aarch64 machine or x86_64 with QEMU offloading.
- Flash tooling via the provided manifest (see Flashing below).
- Unlocked bootloader on the Pro1X.

## Channel setup

Add to `~/.config/guix/channels.scm`:

```scheme
(cons* (channel
        (name 'fxtec-pro1x)
        (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
        (branch "main"))
       %default-channels)
```

Then `guix pull`. For reproducible builds pinned to known-good commits:

```sh
guix pull -C channels-lock.scm
```

GitHub mirror: `https://github.com/mlaparie/fxtec-pro1x-guix`

## Building

```sh
guix system build --system=aarch64-linux systems/minimal.scm
guix system build --system=aarch64-linux systems/mobile.scm
```

The flash script builds automatically; no need to run this first.

**Pre-built artifacts** (u-boot.bin, DTB, rootfs.img) are meant to come from
GitHub Actions on the `main` branch, for those without Guix or an aarch64
build machine.  No CI run has succeeded yet, so none exist.  With them,
`scripts/flash.sh --uboot u-boot-nodtb.bin --rootfs rootfs.img` runs without
Guix if fastboot, mkbootimg, util-linux, e2fsprogs and python3 are
installed (untested).  Such images have no root SSH key.

## Flashing (first install)

**Step 1 — back up** (modem EFS, persist, stock boot images) while Android
is running with ADB root:

```sh
bash scripts/backup-stock.sh    # saves to backup-YYYYMMDD-HHMMSS/
```

**Step 2 — unlock the bootloader** (erases userdata):

```sh
fastboot flashing unlock
```

**Step 3 — flash** (device in fastboot mode):

```sh
guix shell -m manifest.scm -- bash scripts/flash.sh systems/mobile.scm
# or:
guix shell -m manifest.scm -- bash scripts/flash.sh systems/minimal.scm
```

Builds U-Boot, wraps it as an Android boot image, disables vbmeta, erases
`dtbo_a`, flashes boot + rootfs to slot A, reboots.

Log in as `user` (password `123456` — **change it**) on the console or over
USB Ethernet:

```sh
ssh user@172.16.42.1
```

## Updating without reflashing

`scripts/deploy.sh` runs `guix deploy` (`deploy/pro1x.scm`): builds on the
host, copies over SSH as root, adds a generation and activates it, like
`guix system reconfigure`.  Kernel, initrd and firmware changes need a
reboot.  Previous generations are selectable from the U-Boot menu (hold
volume-down at power-on).  Not tested yet.

It logs in as root with your own key.  Create it **before building the image
you flash**, because the image only lets in the key present at build time:

```sh
ssh-keygen -t ed25519 -C pro1x-guix -f ~/.ssh/pro1x-guix
cp ~/.ssh/pro1x-guix.pub keys/pro1x-guix.pub   # not tracked by git
```

Without `keys/pro1x-guix.pub` the image has no root SSH login at all (CI
images never have one).  Then, with the phone on USB:

```sh
bash scripts/deploy.sh                 # systems/mobile.scm to 172.16.42.1
```

## Updates in the long run (plan, not in place yet)

How a phone running this port is meant to stay up to date once the port is
stable.  Today only `scripts/deploy.sh` exists.

- **Three channels.**  The phone's `~/.config/guix/channels.scm` lists `guix`,
  `nonguix` and `fxtec-pro1x` (this public repository).  Updating is plain
  Guix: `guix pull`, then `sudo guix system reconfigure config.scm` with a
  config file you own, based on `systems/mobile.scm`, and `guix package -u`
  for user packages.
- **Substitutes for this channel.**  Guix's servers build Guix proper for
  aarch64; nobody builds this channel's packages (kernel, U-Boot, phosh/phoc,
  ModemManager, libqmi, hexagonrpcd…).  Without a substitute server for them,
  every reconfigure compiles them on the phone, the kernel alone for hours.
  The plan: CI builds the channel and publishes the results (`guix publish`
  or a static cache), and phones add that server and its key.
- **Releases with pinned channels.**  Following the newest commits of Guix
  and nonguix will sometimes break this channel.  A release is a tag here
  plus a channels file pinning the Guix and nonguix commits it was built and
  tested with; CI publishes substitutes for exactly that set, and phones
  update with `guix pull -C <that file>`.  Following the newest commits
  stays possible, at the cost of local builds and breakage.
- **Developer path.**  `scripts/deploy.sh` keeps working alongside: the PC
  builds and pushes a generation to the phone directly.
- **Maintenance.**  The repository owner cuts releases (pin bump, green CI,
  on-device checks); coding agents do the work when asked (see `AGENTS.md`).
- **Shrinking the channel.**  As free parts go upstream (package updates
  to Guix, kernel patches to mainline), this channel narrows to what is
  device-specific: kernel build, firmware, U-Boot, and the Pro1X services.

## Full-disk encryption (LUKS2)

`systems/mobile-encrypted.scm` adds LUKS2 to the same config as `mobile.scm`.
Userdata layout:

```
[0, 256 MiB)  plain ext4 "guixboot"  — kernel, initrd, extlinux.conf
[256 MiB, …)  LUKS2 header + encrypted ext4 root
```

Encryption is applied on the host during flash using `device/fde/xts-encrypt.c`
(AES-256-XTS-plain64); no root or device-mapper needed on the build machine.

**First flash:**
```sh
guix shell -m manifest.scm -- bash scripts/flash-encrypted.sh systems/mobile-encrypted.scm
```

**After `guix system reconfigure`** (on device):
```sh
bash scripts/update-encrypted-boot.sh
```

## Session selection

`systems/mobile.scm` boots into a **greetd + tuigreet** session picker on VT1.
Two sessions are offered:

| Session | Description |
|---|---|
| **Phosh** | phoc-pro1x compositor + phosh-pro1x shell |
| **Sxmo + Sway** | Minimalist sway/Wayland UI via `sxmo_swayinit.sh` |

Desktop files live in `/etc/wayland-sessions/` with absolute store paths in
`Exec=`, so they work regardless of the user's `PATH` at session start.

## Sway fallback

`systems/mobile.scm` also ships `foot`, `sway`, and `wdisplays`. To drop to a
bare sway session from the phone (confirmed working):

```sh
# from a tuigreet session or SSH:
XDG_RUNTIME_DIR=/run/user/1000 sway
```

Or from an existing Wayland session, launch it on a new VT:

```sh
XDG_RUNTIME_DIR=/run/user/1000 WLR_BACKENDS=drm,libinput sway
```

## Services

| Service | What it does |
|---|---|
| `pro1x-hardware-service-type` | udev rules, feedbackd group |
| `pro1x-usb-network-service-type` | USB CDC Ethernet gadget + DHCP |
| `pro1x-keyboard-service-type` | Fn-layer (keyd), xkb layout/variant |
| `pro1x-modem-service-type` | tqftpserv, rmtfs, ModemManager |
| `pro1x-audio-service-type` | UCM2 profiles, WirePlumber S16LE fix, audio-init |
| `pro1x-camera-service-type` | libcamera-pro1x, WirePlumber camera rules |
| `pro1x-sensors-service-type` | hexagonrpcd (ADSP) + iio-sensor-proxy |
| `pro1x-boot-success-service-type` | qbootctl: mark slot A successful |
| `pro1x-boot-menu-service-type` | Previous-generation extlinux entries |

Keyboard layout example:

```scheme
(service pro1x-keyboard-service-type
         (pro1x-keyboard-configuration
          (xkb-layout "us")
          (xkb-variant "")))
```

Sensors: `hexagonrpcd` requires config files from `device/hexagonfs/` (collected
from your device's Android install). Start manually before enabling autostart:

```sh
herd start pro1x-hexagonrpcd
sudo bash tools/sensors-check.sh
```

## Debugging

```sh
herd status                 # list all services
herd log pro1x-audio-init   # view a service log
herd restart pipewire
```

Serial console: `ttyMSM0` at 115200 8N1. Hold volume-down at boot for U-Boot menu.

Kernel log level is `loglevel=4`; raise in `kernel-arguments` for more output.

## Hardware customisation

Module parameters live under `/sys/module/<driver>/parameters/`. Persist via
`kernel-arguments`:

```scheme
(kernel-arguments
 (append '("aw86224.d2s_gain=7" "aw86224.drv2_lvl=100")
         %default-kernel-arguments))
```

- Haptics: `tools/haptics-tune.sh`
- Camera focus: `tools/cam-focus.sh 0..1023` (≈100 = 1 m)
- Charger current: `pro1x_charger_icl.max_icl_ma` (default 1500 mA)

## Other distros

`device/` is distro-independent. Apply the kernel patches and config, install
the UCM2 profiles, run `pro1x-audio-init` at boot, use the keyd config and
udev rules.

## Credits

Kernel, firmware, patches from
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos).
Kernel source from [sm6115-mainline](https://github.com/sm6115-mainline).
Boot image parameters from macneisj's build script and the
[postmarketOS port](https://wiki.postmarketos.org/wiki/F(x)tec_Pro1_X_(fxtec-pro1x)).
