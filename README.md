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
Full-disk encryption             systems/phosh-encrypted.scm + flash-encrypted.sh
```

## Layout

```
fxtec-pro1x/packages/   kernel, u-boot, firmware, audio, misc (phoc, cameractrl, …)
fxtec-pro1x/services/   Shepherd services: audio, boot, camera, fde, hardware, keyboard,
                        modem, sensors, usb-network
systems/minimal.scm     Console + SSH system (baseline)
systems/phosh.scm       Phosh mobile desktop
systems/phosh-encrypted.scm  Phosh with LUKS2 full-disk encryption
device/                 Distro-independent: kernel patches + config, UCM2 profiles,
                        libcamera patches + tuning files, hexagonfs sensor config,
                        phoc patch, keyd config, udev rules, FDE helpers (xts-encrypt.c)
scripts/backup-stock.sh Back up modem EFS and boot partitions before flashing
scripts/flash.sh        Initial flash (plain/unencrypted)
scripts/flash-encrypted.sh  Initial flash with LUKS2 encryption
scripts/update-encrypted-boot.sh  Copy new kernel/initrd to plain boot area after reconfigure
tools/                  On-device diagnostics (haptics-tune, cam-focus, sensors-check, …)
channels.scm            Channel descriptor (unpinned) — add fxtec-pro1x + nonguix to your Guix
channels-lock.scm       Pinned channel commits — reproducible builds; regenerate with guix describe
manifest.scm            Flash tooling manifest — use with guix shell -m manifest.scm
.guix-channel           Channel descriptor for use as a Guix channel
```

## Prerequisites

- GNU Guix with the [nonguix](https://gitlab.com/nonguix/nonguix) channel
  (needed for `linux-firmware`).
- aarch64-linux build support: either a native aarch64 machine, or an x86_64
  host with QEMU user-mode emulation configured for Guix offloading.
- Flash tooling on the build/flash machine: `fastboot`, `mkbootimg`,
  `e2fsprogs`, `util-linux` — on Guix use the provided manifest:
  ```
  guix shell -m manifest.scm -- bash scripts/flash.sh systems/phosh.scm
  ```
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

Then `guix pull` to fetch it. For a fully reproducible build against pinned
channel commits, use `channels-lock.scm` instead:

```sh
guix pull -C channels-lock.scm
```

## Building

From the repository root, with aarch64 cross-compilation or an offload machine:

```sh
guix system build --system=aarch64-linux systems/minimal.scm
# or for the Phosh desktop:
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
guix shell -m manifest.scm -- bash scripts/flash.sh systems/phosh.scm
# or:
guix shell -m manifest.scm -- bash scripts/flash.sh systems/minimal.scm
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

## Full-disk encryption (LUKS2)

`systems/phosh-encrypted.scm` uses the same configuration as `phosh.scm` but adds
LUKS2 encryption. The userdata partition is split:

```
[0, 256 MiB)  plain ext4 "guixboot"  — kernel, initrd, extlinux.conf (U-Boot reads this)
[256 MiB, …)  LUKS2 header + encrypted ext4 root
```

The initrd opens the LUKS2 container (passphrase entered at boot), then mounts
the decrypted ext4 as root. Encryption is done on the host during flash using
`device/fde/xts-encrypt.c` (AES-256-XTS-plain64, same algorithm as dm-crypt),
so no root access or device-mapper is needed on the build machine.

**First flash:**
```sh
guix shell -m manifest.scm -- bash scripts/flash-encrypted.sh systems/phosh-encrypted.scm
```

The script builds U-Boot and the system image, prompts for a passphrase, creates
the LUKS2 container with the encrypted root, and flashes the assembled userdata
image over fastboot.

**After `guix system reconfigure`** (run on the device):
```sh
bash scripts/update-encrypted-boot.sh
```

This copies the new kernel and initrd to the plain `/boot` area so U-Boot can
load them without decrypting. Then reboot.

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
