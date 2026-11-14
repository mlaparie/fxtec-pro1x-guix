# Working on the port

The repository's layout, how images are built and deployed, the services,
the encrypted layout, and what other distributions can reuse.  Coding
agents also follow [AGENTS.md](../AGENTS.md).

## Layout

```
modules/                     The channel's Guile modules (.guix-channel: directory)
modules/fxtec-pro1x/packages/  kernel, u-boot, bootloader, firmware, audio, sensors, gnss,
                             cast, fingerprint, waydroid, power-tools (debug), misc, sxmo
modules/fxtec-pro1x/services/  Shepherd services: audio, boot, camera, channels, fde,
                             fingerprint, hardware, keyboard, modem, sensors,
                             snapshots, usb-network, waydroid
modules/fxtec-pro1x/system/  The systems: common, minimal, mobile
modules/fxtec-pro1x/home.scm The default Guix Home environment (home.md)
systems/minimal.scm          Console + SSH system (baseline)
systems/mobile.scm           Sway, Phosh and Sxmo sessions (greetd/tuigreet)
deploy/pro1x.scm             guix deploy's machine (scripts/deploy.sh)
device/                      Distro-independent: kernel patches + config, UCM2 profiles,
                             libcamera patches + tuning, hexagonfs, keyd, udev rules,
                             FDE helpers (xts-encrypt.c), the Sway session's scripts,
                             fingerprint daemon, package patches (device/patches)
scripts/backup-stock.sh      Back up modem EFS and boot partitions before flashing
scripts/backup-phone.sh      Save the phone's data to the PC before a reflash, restore it after
scripts/flash.sh             Initial flash (plain, or --encrypt)
scripts/flash-encrypted.sh   Initial flash with LUKS2 (flash.sh --encrypt)
scripts/mksparse.py          Sparse parts for fastboot (the encrypted flash's userdata)
scripts/deploy.sh            Update the phone from the PC (guix deploy)
scripts/check-private.sh     Refuse commits that look like they leak device identity
scripts/gen-kernel-config.sh Regenerate device/kernel/config.aarch64
scripts/debug/               On the phone: DAPM logger, greetd login client
tools/                       On-device diagnostics: haptics (tune, check), camera focus,
                             sensors (check, collect), charger status, fuel gauge
                             probe; fde-qemu-test.py (an image in QEMU, on the PC)
docs/                        Install, configure, use, update, troubleshoot, develop
rag-notes/                   Findings (hardware, guix, nixos→guix; README.md)
NEWS.md, TODO.org            Release notes; the state file (Org: tasks, states, priorities)
channels.scm                 Channel descriptor (unpinned)
channels-lock.scm            Pinned channel commits for reproducible local builds
channels-ci.scm              Pinned guix+nonguix for CI (fxtec-pro1x loaded via -L modules)
manifest.scm                 Flash tooling: fastboot, mkbootimg, util-linux, e2fsprogs
.guix-channel                Channel descriptor for use as a Guix channel
```

## Building

You need GNU Guix with the [nonguix](https://gitlab.com/nonguix/nonguix)
channel (for `linux-firmware`), and aarch64 builds: an aarch64 machine, or
x86_64 with QEMU binfmt (`--system=aarch64-linux`).

```sh
guix system build -L modules --system=aarch64-linux systems/minimal.scm
guix system build -L modules --system=aarch64-linux systems/mobile.scm
```

`scripts/flash.sh` builds by itself; there is no need to run this first.
It builds U-Boot, wraps it as an Android boot image, disables vbmeta,
erases `dtbo_a`, and flashes boot and the root to slot A.  Before
building, it makes a key pair on the PC, `~/.ssh/pro1x-guix`, if there is
none: the flashed system lets it log in as root for `scripts/deploy.sh`.

**Release images.**  CI (GitHub Actions, natively on aarch64) builds the
root image on pushes to `main` and on `v*` tags; a tag also makes a GitHub
release with the notes from NEWS.md.  The image comes as
`rootfs.img.zst.part0`, `part1`…, joined and unpacked with
`cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, with
`u-boot-nodtb.bin` and the DTB.  `scripts/flash.sh --uboot
u-boot-nodtb.bin --rootfs rootfs.img` then runs without Guix if fastboot,
mkbootimg, util-linux, e2fsprogs and python3 are installed (untested).
Such images have no root SSH key.

## Deploying from the PC

`scripts/deploy.sh` builds on the PC what `sudo guix system reconfigure
~/.config/guix/config.scm` would build on the phone, and installs it:

1. it copies the phone user's `~/.config/guix/config.scm` and `channels.scm`
   (or `/etc/guix`'s if the user has none), and `~/.ssh/*.pub`;
2. it runs `guix deploy` (`deploy/pro1x.scm`) under `guix time-machine`
   with the phone's channels, so your changes in `config.scm` are kept;
3. it copies the result over SSH as root, adds a generation and
   activates it.  Kernel, initrd and firmware changes need a reboot.

`-L modules` puts this tree's modules in front of the channel's, so
unpushed changes to the port are tested on top of your configuration.
`bash scripts/deploy.sh --repo [system-file]` deploys a system file from
this tree instead, replacing your configuration.

It logs in as root with `~/.ssh/pro1x-guix` (without a passphrase: guix
deploy cannot ask for one), and keeps that key in root's authorized keys
whatever `config.scm` says.  Images flashed from a ready-made root
(`--rootfs`, CI images) have no root SSH login: add the key to
`/root/.ssh/authorized_keys` once by hand.

## Updates in the long run (plan, not in place yet)

How a phone running this port is meant to stay up to date once the port is
stable.  Today: `scripts/deploy.sh`, or `guix pull` and a reconfigure on
the phone with the pinned channels (which builds this channel's packages
there).

- **Three channels.**  The phone's `~/.config/guix/channels.scm` lists `guix`,
  `nonguix` and `fxtec-pro1x`.  Updating is plain Guix: `guix pull`, then
  `sudo guix system reconfigure` with your `config.scm`, which inherits the
  port's system.
- **Substitutes for this channel.**  Guix's servers build Guix proper for
  aarch64; nobody builds this channel's packages (kernel, U-Boot, phosh/phoc,
  ModemManager, libqmi, hexagonrpcd…).  Without a substitute server for them,
  every reconfigure compiles them on the phone, the kernel alone for hours.
  The plan: CI builds the channel and publishes the results (`guix publish`
  or a static cache), and phones add that server and its key.
- **Releases with pinned channels.**  A release is a tag here plus a
  channels file pinning the Guix and nonguix commits it was built and
  tested with; CI publishes substitutes for exactly that set, and phones
  update with `guix pull -C <that file>`.
- **Shrinking the channel.**  As free parts go upstream (package updates
  to Guix, kernel patches to mainline), this channel narrows to what is
  device-specific: kernel build, firmware, U-Boot, and the Pro¹x services.

## Services

| Service | What it does |
|---|---|
| `pro1x-hardware-service-type` | udev rules; notification and charge LEDs, charge limit, idle dim/blank/lock, double tap to wake, pocket detection, torch guard, key haptics, light/dark theme, lock-screen keyboard (fields in [configure.md](configure.md)) |
| `pro1x-usb-network-service-type` | USB CDC Ethernet gadget + DHCP |
| `pro1x-keyboard-service-type` | Fn layer (keyd), xkb layout/variant |
| `pro1x-modem-service-type` | tqftpserv, rmtfs, ModemManager, 81voltd |
| `pro1x-audio-service-type` | UCM2 profiles, WirePlumber S16LE fix, audio-init |
| `pro1x-camera-service-type` | libcamera-pro1x, WirePlumber camera rules |
| `pro1x-sensors-service-type` | hexagonrpcd (ADSP) + iio-sensor-proxy |
| `pro1x-boot-success-service-type` | qbootctl: mark slot A successful |
| `pro1x-boot-menu-service-type` | Previous-generation extlinux entries |
| `waydroid-service-type` | Waydroid's bus policy, D-Bus activation and polkit actions; start at login |

Sessions: greetd and tuigreet on VT1 offer Sway, Phosh, and Sxmo + Sway
(which needs superd, not packaged yet).  Session files in
`/etc/wayland-sessions/` use store paths in `Exec=`.

Sensors: `hexagonrpcd` needs config files from `device/hexagonfs/`
(collected from the phone's Android install).  To check them by hand:

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

The kernel's log level is `loglevel=4`; raise it in `kernel-arguments` for
more output.  More logs: [troubleshoot.md](troubleshoot.md).

Module parameters live under `/sys/module/<driver>/parameters/`.  To keep
them, put them in `kernel-arguments`:

```scheme
(kernel-arguments
 (append '("aw86224.d2s_gain=7" "aw86224.drv2_lvl=100")
         %default-kernel-arguments))
```

- Haptics: `tools/haptics-tune.sh`
- Camera focus: `tools/cam-focus.sh 0..1023` (≈100 = 1 m)
- Charger current: `pro1x_charger_icl.max_icl_ma` (default 1500 mA)
- Keyboard scan while a key is held: `pro1x_aw9523_kbd.poll_ms` (default 5)

## Full-disk encryption (LUKS2)

Encryption is chosen at the flash (`scripts/flash.sh --encrypt`), and
there is nothing to set in `config.scm`: the same system boots on both
layouts.  Its initrd reads the layout from the disk and asks for a
passphrase only on the encrypted one; `/boot` is mounted from the plain
area if there is one.  Every initrd carries the unlock tools for this,
about 1.6 MB.  Userdata layout:

```
[0, 512 MiB)    plain ext4 "guixboot": kernels, initrds, extlinux.conf for U-Boot
[512 MiB, end)  LUKS2 header + encrypted root
```

The encryption is applied on the PC during the flash
(`device/fde/xts-encrypt.c`, AES-256-XTS-plain64; no root or device-mapper
needed there).  The kernel and initrd stay unencrypted, and the bootloader
unlocked: this protects data while the phone is off, not against someone
tampering with it.  The passphrase prompt has the plain US layout.

The `pro1x-boot-menu` service copies the current system and four previous
ones to the plain area when Guix writes its boot configuration.
`tools/fde-qemu-test.py` boots such an image in QEMU, to test changes
without the phone.

## Other distributions

`device/` is distribution-independent.  Apply the kernel patches and
config, install the UCM2 profiles, run `pro1x-audio-init` at boot, and use
the keyd config and udev rules.
