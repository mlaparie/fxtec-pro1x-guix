> **Developer preview.**  Calls, SMS, MMS, mobile data, Wi-Fi, audio,
> cameras and sensors work; GPS, speakerphone and suspend do not yet
> (status below).  Do not flash this on a device you depend on.

# Guix System on the F(x)tec Pro¹x (QX1050)

Mainline Linux and U-Boot for the F(x)tec Pro¹x (SM6115 / Snapdragon 662),
packaged as a GNU Guix channel. Port of
[nyymi609/fxtec-pro1x-nixos](https://github.com/nyymi609/fxtec-pro1x-nixos);
kernel patches, firmware, and flash approach originate there.

> Flashing **erases userdata** and replaces the bootloader on slot A.
> Back up first (`scripts/backup-stock.sh`). Unlock the bootloader before
> doing anything.

## Documentation

| page | |
|---|---|
| [docs/features.md](docs/features.md) | what it is and what works |
| [docs/install.md](docs/install.md) | flashing the first time; reflashing with a backup of your data |
| [docs/usage.md](docs/usage.md) | daily use: sessions, keys, swipes and menus, screen, network, passwords; the change-deploy-rollback loop |
| [docs/configure.md](docs/configure.md) | your config.scm and channels, the port's options |
| [docs/home.md](docs/home.md) | home files: managed, seeded once, or left alone (Guix Home) |
| [docs/update.md](docs/update.md) | updating, generations, rollback |
| [docs/channels.md](docs/channels.md) | why pins, the channel files, adding channels, Guix on a phone vs a desktop |
| [docs/troubleshoot.md](docs/troubleshoot.md) | logs, known problems, recovery |

The rest of this README is the reference for working on the port.

## Port status

As observed on the phone (2026-11-06, Linux 7.3).  Phone comforts and the
Sway session: [features.md](docs/features.md).

```
Display (BOE AMOLED, 60 Hz)      Working
GPU (Adreno 610)                 Working    freedreno; phoc renders on the GPU
Touchscreen                      Working
Auto-rotation                    Working    portrait with the keyboard closed, landscape out; optional sensor rotation
Hardware keyboard                Working    AW9523B driver, Fn layer via keyd
Keyboard backlight               Working    on while slid out; off after 60 s without a key (configurable)
Keyboard slider switch           Working    backlight, rotation, on-screen keyboard
Volume keys                      Working    Phosh (gsd-media-keys), Sway
Wi-Fi                            Working    firmware via tqftpserv over QRTR
Bluetooth                        Working    on/off, scan, pairing, audio to a speaker
USB gadget (Ethernet)            Working    172.16.42.1 SSH; requires host udev/network setup
Speaker                          Working
Earpiece                         Working    in calls
Headphones                       Untested
Microphones                      Working    in calls
Vibration motor                  Working    feedbackd
Calls                            Partial    both directions, earpiece and speaker; on 4G through VoLTE (81voltd); mute has no effect yet
SMS                              Working    Chatty
MMS                              Working    mmsd-tng + Chatty
Mobile data                      Working    3G and 4G
Rear and front cameras           Partial    preview and photos in GNOME Snapshot; very early (focus, exposure, rotation)
Accelerometer                    Working    SSC via hexagonrpcd + libssc + iio-sensor-proxy 3.9
Proximity sensor                 Working    calls (Sway), no wake in a pocket
Light sensor, gyroscope          Untested
Battery                          Working    UPower: level and charging state in Phosh
Screen dimming, blank, lock      Working    dim at 150 s, off at 180 s, locked 2 min later (configurable)
Double tap to wake               Working    not in a pocket (configurable)
Fingerprint reader               Working    unlocks the Sway lock screen while it is lit; fingers managed in quick actions
Suspend                          Untested
GPS                              Not yet    modem's location service gives no NMEA (see TODO.org)
NFC, video codecs                Untested
Full-disk encryption             Working    flash.sh --encrypt (first flashed 2026-11-05)
```

## Layout

```
modules/                     The channel's Guile modules (.guix-channel: directory)
modules/fxtec-pro1x/packages/  kernel, u-boot, bootloader, firmware, audio, sensors, gnss,
                             cast, fingerprint, power-tools (debug), misc, sxmo
modules/fxtec-pro1x/services/  Shepherd services: audio, boot, camera, channels, fde,
                             fingerprint, hardware, keyboard, modem, sensors,
                             snapshots, usb-network
modules/fxtec-pro1x/system/  The systems: common, minimal, mobile
modules/fxtec-pro1x/home.scm The default Guix Home environment (docs/home.md)
systems/minimal.scm          Console + SSH system (baseline)
systems/mobile.scm           Sway, Phosh and Sxmo sessions (greetd/tuigreet)
deploy/pro1x.scm             guix deploy's machine (scripts/deploy.sh)
device/                      Distro-independent: kernel patches + config, UCM2 profiles,
                             libcamera patches + tuning, hexagonfs, keyd, udev rules,
                             FDE helpers (xts-encrypt.c), the Sway session's scripts,
                             fingerprint daemon, package patches (device/patches)
scripts/backup-stock.sh      Back up modem EFS and boot partitions before flashing
scripts/backup-phone.sh      Save the phone's data to the PC before a reflash, restore it after
scripts/flash.sh             Initial flash (plain)
scripts/flash-encrypted.sh   Initial flash with LUKS2 (flash.sh --encrypt)
scripts/mksparse.py          Sparse parts for fastboot (the encrypted flash's userdata)
scripts/deploy.sh            Update the phone from the PC (guix deploy)
scripts/check-private.sh     Refuse commits that look like they leak device identity
scripts/gen-kernel-config.sh Regenerate device/kernel/config.aarch64
scripts/debug/               On the phone: DAPM logger, greetd login client
tools/                       On-device diagnostics: haptics (tune, check), camera focus,
                             sensors (check, collect), charger status, fuel gauge
                             probe; fde-qemu-test.py (an image in QEMU, on the PC)
docs/                        Install, configure, use, update, troubleshoot
rag-notes/                   Findings (hardware, guix, nixos→guix; README.md)
NEWS.md, TODO.org            Release notes; the state file (Org: tasks, states, priorities)
channels.scm                 Channel descriptor (unpinned)
channels-lock.scm            Pinned channel commits for reproducible local builds
channels-ci.scm              Pinned guix+nonguix for CI (fxtec-pro1x loaded via -L modules)
manifest.scm                 Flash tooling: fastboot, mkbootimg, util-linux, e2fsprogs
.guix-channel                Channel descriptor for use as a Guix channel
```

## Prerequisites

- GNU Guix with the [nonguix](https://gitlab.com/nonguix/nonguix) channel (for `linux-firmware`).
- aarch64 build support: native aarch64 machine or x86_64 with QEMU offloading.
- Flash tooling via the provided manifest (see Flashing below).
- Unlocked bootloader on the Pro¹x.

## Channel setup

`channels.scm` lists the three channels a Pro¹x system follows: guix,
nonguix and fxtec-pro1x (the phone ships the same file as
`/etc/guix/channels.scm`).  Copy it to `~/.config/guix/channels.scm`, add
your own channels, then `guix pull`.

**guix and nonguix are pinned** to the commits the port is built and
tested with.  No substitute server builds this channel's packages yet, so
with any other guix or nonguix commit, a pull followed by a reconfigure
makes the phone build the kernel, Phosh and much of their dependencies
itself, for hours.  The pins move with the port's releases; remove them
only if you accept those builds (or build on a PC and deploy).

`channels-lock.scm` pins the same guix and nonguix commits and is what
release builds use.

GitHub mirror: `https://github.com/mlaparie/fxtec-pro1x-guix`

## Building

```sh
guix system build -L modules --system=aarch64-linux systems/minimal.scm
guix system build -L modules --system=aarch64-linux systems/mobile.scm
```

The flash script builds automatically; no need to run this first.

**Pre-built artifacts** (rootfs.img.zst.part0, part1…, to join and unpack
with `cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, and
u-boot-nodtb.bin plus the DTB when
the CI U-Boot build succeeds) come with each release on GitHub (`v*` tags,
release notes in NEWS.md), for those without Guix or an aarch64 build
machine.  With them,
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
`dtbo_a`, flashes boot + rootfs to slot A, reboots.  Before building, it
makes a key pair on your PC, `~/.ssh/pro1x-guix`, if there is none: the
flashed system lets it log in as root for `scripts/deploy.sh`, and keeps
its public half on the phone as `~/.ssh/pro1x-guix.pub` (see "Your system
configuration").

Log in as `user` (password `123456` — **change it**) on the console or over
USB Ethernet:

```sh
ssh user@172.16.42.1
```

## Your system configuration

As flashed, the phone runs the port's system unchanged.  To customise it
beyond that (your own packages, services, users, timezone, channels),
copy the starting files the phone ships into `~/.config/guix/` and edit
them there (`home.scm` is your Guix Home: your packages and home files):

```sh
cp /etc/guix/config.scm /etc/guix/channels.scm /etc/guix/home.scm ~/.config/guix/
guix pull                    # then log out and back in once
sudo guix system reconfigure ~/.config/guix/config.scm
```

- `channels.scm` lists guix, nonguix and fxtec-pro1x, with guix and
  nonguix pinned so the phone does not rebuild the kernel and Phosh
  itself (see "Channel setup"); add your own channels to it.
- `config.scm` inherits the port's system from the channel
  (`pro1x-mobile-operating-system` in `(fxtec-pro1x system mobile)`), so
  `guix pull` keeps bringing the port's fixes while your changes stay in
  your file.  It shows where your changes go.  It holds no key and no
  password, so you can keep it with your other dotfiles.
- Root SSH login is off in it (`#:root-ssh-keys` commented out).
  `scripts/deploy.sh` keeps your PC's key in root's authorized keys
  whatever the file says, so deploys keep working; the line matters only
  for root SSH after a reconfigure on the phone.

Do not start from `/run/current-system/configuration.scm`: that is the
port's own system file, not meant to be edited.  `guix system
delete-generations`, `roll-back` and `switch-generation` work on the phone
and refresh the U-Boot menu.

## Updating without reflashing

`scripts/deploy.sh` builds on your PC what `sudo guix system reconfigure
~/.config/guix/config.scm` would build on the phone, and installs it:

1. it copies the phone user's `~/.config/guix/config.scm` and `channels.scm`
   (or `/etc/guix`'s if the user has none), and `~/.ssh/*.pub`;
2. it runs `guix deploy` (`deploy/pro1x.scm`) under `guix time-machine`
   with the phone's channels, so your changes in `config.scm` are kept;
3. it copies the result over SSH as root, adds a generation and
   activates it.  Kernel, initrd and firmware changes need a reboot.

Previous generations are selectable from the U-Boot menu (hold
volume-down at power-on).  `-L modules` puts this tree's modules in front
of the channel's, so unpushed changes to the port are tested on top of
your configuration.  `bash scripts/deploy.sh --repo [system-file]`
deploys a system file from this tree instead, replacing your
configuration.

It logs in as root with the key `scripts/flash.sh` makes on your PC,
`~/.ssh/pro1x-guix` (without a passphrase: guix deploy cannot ask for
one), and keeps that key in root's authorized keys whatever `config.scm`
says.  Images flashed from a ready-made rootfs (`--rootfs`, CI images)
have no root SSH login: add the key to `/root/.ssh/authorized_keys` once
by hand.  With the phone on USB:

```sh
bash scripts/deploy.sh                 # the phone's own configuration
bash scripts/deploy.sh --repo          # systems/mobile.scm from this tree
```

## Your home configuration

The port's Sway, bar and foot settings live outside your home and follow
every deploy; the files in `~/.config` only add to them
([configure.md](docs/configure.md#files-outside-configscm)).  For other
home files and your own packages, Guix Home manages them from
`~/.config/guix/home.scm`, which `config.scm` includes
([home.md](docs/home.md)).

New accounts also get Guix's default `~/.bash_profile` (it loads your
`guix pull` profile) and `~/guix-home-config.scm`, Guix's file for a
standalone `guix home reconfigure`; the port does not use it (Guix Home is
part of the system here), and there is no `~/.bashrc` until you set one.

## Updates in the long run (plan, not in place yet)

How a phone running this port is meant to stay up to date once the port is
stable.  Today: `scripts/deploy.sh`, or `guix pull` and a reconfigure on
the phone with the pinned channels (which builds this channel's packages
there).

- **Three channels.**  The phone's `~/.config/guix/channels.scm` lists `guix`,
  `nonguix` and `fxtec-pro1x` (this public repository).  Updating is plain
  Guix: `guix pull`, then `sudo guix system reconfigure` with your
  `config.scm`, which inherits the port's system; `guix package -u` for
  user packages.
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
  device-specific: kernel build, firmware, U-Boot, and the Pro¹x services.

## Full-disk encryption (LUKS2)

Flashed on the author's phone on 2026-11-05: U-Boot reads the plain area, the
passphrase is typed on the slide-out keyboard at the prompt, and the root grows to
the partition on first boot.  `tools/fde-qemu-test.py` boots such an image in QEMU,
to test changes without the phone.

Encryption is chosen at the flash, and there is nothing to set in `config.scm`: the
same system boots on both layouts.  Its initrd reads the layout from the disk and asks
for a passphrase only on this one; `/boot` is mounted from the plain area if there is
one.  Every initrd carries the unlock tools for this, about 1.6 MB.  Userdata layout:

```
[0, 512 MiB)    plain ext4 "guixboot": kernels, initrds, extlinux.conf for U-Boot
[512 MiB, end)  LUKS2 header + encrypted ext4 root
```

The encryption is applied on the PC during the flash (`device/fde/xts-encrypt.c`,
AES-256-XTS-plain64; no root or device-mapper needed there).  The kernel and initrd
stay unencrypted, and the bootloader unlocked: this protects data while the phone is
off, not against someone tampering with it.

**First flash** (erases userdata; asks for the passphrase, which you then type on
the slide-out keyboard at each boot: the prompt has the plain US layout, so a
symbol is where a US keyboard has it):
```sh
bash scripts/flash.sh --encrypt
```

**Updates:** `scripts/deploy.sh` or `guix system reconfigure` as usual.  The
`pro1x-boot-menu` service copies the current system and four previous ones to the
plain area when Guix writes its boot configuration.

## Keyboard

Layout: US international (`us` + `intl`).  The keys that differ from a PC
keyboard are remapped by keyd (`device/input/keyd.conf`), after the Pro1
keymap from droidian-devices/linux-android-fxtec-pro1 PR #2:

```
 Base layer: what each key types (keyd, then us-intl)
 ─────────────────────────────────────────────────────────────────────
  esc  1    2    3    4    5    6    7    8    9    0    -    =    bspc
  tab  q    w    e    r    t    y    u    i    o    p    [    ]    del
    caps a    s    d    f    g    h    j    k    l    ?:   '    ret
  sft  `~   z    x    c    v    b    n    m    ,    .    /|   up   sft
  ctl  sup  fx   alt  \|   spc ──────────────  ctl  sup  lft  down rght

 Fn layer: hold fx (· = as in the base layer)
 ─────────────────────────────────────────────────────────────────────
  ·    f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  sclk
  ·    ·    wlan ·    ·    ·    ·    ·    ·    ·    \    bri- bri+ ins
    ·    ·    ·    ·    ·    ·    ·    ·    ·    ;    play mute menu
  ·    ·    ·    ·    ·    ·    bt   ·    ·    vol- vol+ |    pgup ·
  ·    ·    fx   ·    agr  · ────────────────  ·    ·    home pgdn end

  sup   yellow slant arrows: Super, the sway modifier ($mod)
  fx    F(x) key: hold for the Fn layer
  \|    key labelled Sym: \ (Shift: |); with fx it is AltGr (agr),
        so fx+Sym+letter types é, ñ etc. on us-intl
  ?:    the key right of l types ? (Shift: :)
  /|    the key left of up types / (Shift: |)
  ; \ |  on fx+l, fx+p, fx+/ as on the yellow keycaps
  `~    sends 102nd, remapped to ` (Shift: ~; dead keys on us-intl)
  wlan, bt   rfkill keys for Wi-Fi and Bluetooth
  fx+alt+p   screenshot (with Ctrl: a region)
  bri-, bri+, vol-, vol+, play, mute   screen brightness, volume, media

 Sway (Super = yellow arrow); all of them: Super+Ctrl+h
 ─────────────────────────────────────────────────────────────────────
  Super+Return, +Shift        terminal (foot server), plain foot
  Super+q, Super+m, Super+Tab quick actions, launcher, window switcher
  Super+BackSpace, +Shift+q   close window
  Super+1…0, Ctrl+Super+1…0   go to / move to workspace; Super+; back
  Alt/Shift+Super+1…0         numbered scratchpad: put away / bring back
  Super+arrows, +Shift        focus, move
  Super+f, Super+space        fullscreen, floating
  Super+h, Super+v            split vertically, horizontally
  Super+e, Super+w, Super+r   split layout, tabs, resize mode
  Super+o, Ctrl+Super+o       window opacity up, down
  Super+i, Super+b            on-screen keyboard, bar
  Ctrl+Super+l, both volume keys   lock
  Super+Shift+r, +Shift+e     reload sway, exit sway
  Power key, camera button    panel off / on; Snapshot, take a picture
```

`keyd monitor` (as root) shows what each key sends.

The keyboard backlight is on while the keyboard is slid out and the screen
is on (service `pro1x-kbd-backlight`).  Sliding the keyboard out with the
screen off turns the screen on in sway (not yet in Phosh).  To switch the
light by hand: `brightnessctl -d white:kbd_backlight set 0` (or `1`); it
stays that way until the next slide or screen change.

## Sessions

greetd + tuigreet on VT1 offers, in this order (it remembers the last user
and session):

| Session | |
|---|---|
| **Sway** | the port's config in `/etc/sway/pro1x.d/`, yours in `~/.config/sway/config` ([configure.md](docs/configure.md#files-outside-configscm)); see [features.md](docs/features.md#sway-on-the-phone) |
| **Phosh** | phoc-pro1x + phosh-pro1x |
| **Sxmo + Sway** | needs superd (not packaged yet) |

Session files in `/etc/wayland-sessions/` use store paths in `Exec=`.

## Services

| Service | What it does |
|---|---|
| `pro1x-hardware-service-type` | udev rules; notification and charge LEDs, charge limit, idle dim/blank/lock, double tap to wake, pocket detection, torch guard, key haptics, light/dark theme, lock-screen keyboard (fields in [configure.md](docs/configure.md)) |
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

Hold volume-down at power-on for the U-Boot menu (earlier generations).

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
