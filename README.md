# Guix System on the F(x)tec Pro1X (QX1050)

Mainline Linux (plus a set of small device patches) and U-Boot for the
F(x)tec Pro1X (Snapdragon 662 / SM6115), packaged as a GNU Guix channel. Use
it as a ready-made Phosh system (`systems/phosh.scm`) or adapt `systems/minimal.scm`
into your own configuration.

This is a port of [nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos)
to GNU Guix. The kernel patches, firmware, device files and flash approach all
originate from that project; the Guix packaging and service layer are new here.

> Nothing here is guaranteed. Flashing **erases userdata** and replaces the
> bootloader on slot A. Back up critical partitions first (`scripts/backup-stock.sh`).
> Unlock the bootloader before doing anything.

## Port status

This is an initial port. The kernel and firmware are identical to the NixOS
port (same source pins); hardware that works there is expected to work here.
Items marked *untested* have not yet been verified on a Guix-flashed device.

```
Display (BOE AMOLED, 60 Hz)      Expected
GPU (Adreno 610)                 Expected
Touchscreen                      Expected
Hardware keyboard                Expected   AW9523B driver, backlight, Fn layer via keyd
Keyboard slider switch           Expected   phoc is patched to not crash on this switch
Wi-Fi                            Expected   firmware served by tqftpserv over QRTR
Bluetooth                        Expected
USB gadget (Ethernet)            Expected   172.16.42.1, SSH access
Speaker / earpiece / headphones  Expected
Microphones                      Expected
Calls                            Untested
SMS / mobile data                Untested
Rear camera (IMX582)             Untested   libcamera-pro1x built with sensor patches
Front camera (S5K4H7)            Untested
Sensors (accel, gyro, ALS, prox) Untested   ADSP via hexagonrpcd + iio-sensor-proxy
Vibration motor                  Expected
Battery / charging               Expected
Suspend                          Untested
GPS, NFC, video codecs           Untested
Full-disk encryption             Not ported
```

## Layout

```
fxtec-pro1x/packages/   kernel, u-boot, firmware, audio, misc (phoc, cameractrl, …)
fxtec-pro1x/services/   Shepherd services: audio, boot, camera, hardware, keyboard,
                        modem, sensors, usb-network
systems/minimal.scm     Console + SSH system (baseline)
systems/phosh.scm       Phosh mobile desktop
device/                 Distro-independent: kernel patches + config, UCM2 profiles,
                        libcamera patches + tuning files, hexagonfs sensor config,
                        phoc patch, keyd config, udev rules
scripts/                flash.sh, backup-stock.sh, update.sh, deploy.sh, …
tools/                  On-device diagnostics (haptics-tune, cam-focus, sensors-check, …)
channels.scm            Channel pins for reproducible builds
.guix-channel           Channel descriptor for use as a Guix channel
```

## Prerequisites

- GNU Guix with the [nonguix](https://gitlab.com/nonguix/nonguix) channel
  (needed for `linux-firmware` and `firefox`).
- aarch64-linux build support: either a native aarch64 machine, or an x86_64
  host with QEMU user-mode emulation configured for Guix offloading.
- `fastboot` and `mkbootimg` (android-tools) on the build/flash machine.
- `e2label` (e2fsprogs) on the build/flash machine.
- An unlocked bootloader on the Pro1X.

Add the channel to your `~/.config/guix/channels.scm` (or copy `channels.scm`
from this repo):

```scheme
(cons* (channel
        (name 'fxtec-pro1x)
        (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
        (branch "guix"))
       %default-channels)
```

Then `guix pull` to fetch it.

## Building

From the repository root, with aarch64 cross-compilation or an offload machine:

```sh
guix system build --system=aarch64-linux systems/minimal.scm
# or for the Phosh desktop (builds Firefox — allow several hours on aarch64):
guix system build --system=aarch64-linux systems/phosh.scm
```

The flash script builds everything automatically, so you do not need to run
this separately before flashing.

## Flashing (first install)

**Step 1 — back up critical partitions** (modem EFS, persist, stock boot images).
Do this while Android is still running; ADB with root access is required:

```sh
bash scripts/backup-stock.sh          # saves to backup-YYYYMMDD-HHMMSS/
```

Store the backup somewhere safe off the device. See the script for EDL fallback
instructions if ADB root is unavailable.

**Step 2 — unlock the bootloader** (erases userdata):

```
fastboot flashing unlock
```

**Step 3 — flash**. Put the phone in fastboot mode, then from the repo root:

```sh
bash scripts/flash.sh systems/phosh.scm
# or:
bash scripts/flash.sh systems/minimal.scm
```

The script builds U-Boot and the system image, wraps U-Boot as an Android boot
image (required by the ABL), disables vbmeta verification, erases the Android
device-tree overlay (`dtbo_a`), flashes boot + rootfs to slot A, and reboots.

First boot initialises the Guix store; allow a couple of minutes. Log in as
`user` (password `123456` — **change it**) on the console or over USB Ethernet:

```sh
ssh user@172.16.42.1
```

## Updating without reflashing

After the first flash, subsequent updates do not need fastboot:

```sh
guix system build --system=aarch64-linux systems/phosh.scm
bash scripts/update.sh
```

Reboot to switch to the new generation. Previous generations remain selectable
from the U-Boot menu (hold volume-down at power-on).

## Services

The Pro1X services live in `fxtec-pro1x/services/`. They are included in both
system configurations and can be adjusted there:

| Service | What it does |
|---|---|
| `pro1x-hardware-service-type` | udev rules, feedbackd group |
| `pro1x-usb-network-service-type` | USB CDC Ethernet gadget + DHCP server |
| `pro1x-keyboard-service-type` | Fn-layer (keyd), xkb layout and variant |
| `pro1x-modem-service-type` | tqftpserv (Wi-Fi + modem firmware), rmtfs, ModemManager |
| `pro1x-audio-service-type` | UCM2 profiles, WirePlumber S16LE fix, audio-init mixer |
| `pro1x-camera-service-type` | libcamera-pro1x, WirePlumber camera rules |
| `pro1x-sensors-service-type` | hexagonrpcd (ADSP sensors) + iio-sensor-proxy |
| `pro1x-boot-success-service-type` | qbootctl: marks slot A successful after every boot |
| `pro1x-boot-menu-service-type` | previous-generation extlinux entries for U-Boot |

Keyboard layout example:

```scheme
(service pro1x-keyboard-service-type
         (pro1x-keyboard-configuration
          (xkb-layout "us")
          (xkb-variant "")))
```

Sensors note: `hexagonrpcd` serves config files from `device/hexagonfs/` (collected
from this unit's Android install). Start it manually before enabling autostart:

```sh
herd start pro1x-hexagonrpcd
sudo bash tools/sensors-check.sh
```

## Debugging

Shepherd (the Guix init system):

```sh
herd status                    # list all services
herd log pro1x-audio-init      # view a service log
herd restart pipewire
```

Serial console: the debug UART is `ttyMSM0` at 115200 8N1 (hardware header).
Hold volume-down at boot for the U-Boot menu.

Kernel log level is `loglevel=4`; increase in `kernel-arguments` for more output.

## Hardware customisation

Device drivers expose module parameters under `/sys/module/<driver>/parameters/`.
Make them permanent via `kernel-arguments` in the system config:

```scheme
(kernel-arguments
 (append '("aw86224.d2s_gain=7" "aw86224.drv2_lvl=100")
         %default-kernel-arguments))
```

- Haptics (`aw86224`): `tools/haptics-tune.sh` sweeps through gain/drive levels.
- Camera focus: `tools/cam-focus.sh 0..1023` (≈100 = 1 m, higher = closer).
- Charger current: `pro1x_charger_icl.max_icl_ma` (default 1500 mA).

## Other distros

`device/` is distro-independent. Apply the kernel patches and config, install
the UCM2 profiles into alsa-ucm-conf, run `pro1x-audio-init` at boot, and use
the keyd config and udev rules from `device/`.

## Credits

Kernel, firmware, device patches and overall architecture from
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos).
Kernel source and firmware blobs from the
[sm6115-mainline](https://github.com/sm6115-mainline) project. Boot image
parameters and flash knowledge from macneisj's Pro1X build script and the
[postmarketOS port](https://wiki.postmarketos.org/wiki/F(x)tec_Pro1_X_(fxtec-pro1x)).
