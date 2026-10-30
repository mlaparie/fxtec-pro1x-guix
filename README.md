> **Work in progress.**  Display, touch, GPU, keyboard, Wi-Fi, speaker,
> cameras, auto-rotation and 3G data work; LTE, GPS, calls, SMS and
> microphones do not yet (status below).  Do not flash this on a device
> you depend on.

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
| [docs/install.md](docs/install.md) | flashing the first time |
| [docs/usage.md](docs/usage.md) | daily use: sessions, keys, screen, network; the change-deploy-rollback loop |
| [docs/configure.md](docs/configure.md) | your config.scm and channels, the port's options |
| [docs/update.md](docs/update.md) | updating, generations, rollback |
| [docs/channels.md](docs/channels.md) | why pins, the channel files, adding channels, Guix on a phone vs a desktop |
| [docs/troubleshoot.md](docs/troubleshoot.md) | logs, known problems, recovery |

The rest of this README is the reference for working on the port.

## Port status

As observed on the phone (2026-10-30, Linux 7.1, branch `main`). "Untested"
means nobody has tried it on this port yet.

```
Display (BOE AMOLED, 60 Hz)      Working
GPU (Adreno 610)                 Working    freedreno; phoc renders on the GPU
Touchscreen                      Working
Auto-rotation                    Working    Phosh; landscape locked while the keyboard is out
Hardware keyboard                Working    AW9523B driver, Fn layer via keyd
Keyboard backlight               Working    on while slid out; off after 60 s without a key (configurable)
Keyboard slider switch           Working    backlight, Phosh landscape, wakes sway
Volume keys                      Working    Phosh (gsd-media-keys); Sway untested
Wi-Fi                            Working    firmware via tqftpserv over QRTR
Bluetooth                        Working    on/off, scan, pairing, audio to a speaker
USB gadget (Ethernet)            Working    172.16.42.1 SSH; requires host udev/network setup
Speaker                          Working    pops at login (open)
Earpiece                         Working    in calls
Headphones                       Untested
Microphones                      Working    in calls
Vibration motor                  Working    feedbackd (calls, notifications); Sway untested
Calls                            Working    receiving a call works; speaker and mute buttons need callaudiod (fix pending test)
SMS                              Working    Chatty
MMS                              Not yet    needs mmsd-tng (not packaged yet)
Mobile data                      Partial    3G works; no LTE yet (see TODO.md)
Rear and front cameras           Partial    preview and photos in GNOME Snapshot; very early (focus, exposure, rotation)
Accelerometer                    Working    SSC via hexagonrpcd + libssc + iio-sensor-proxy 3.9
Proximity, light, gyroscope      Untested
Battery                          Working    UPower: level and charging state in Phosh
Screen dimming                   Working    20% after 60 s idle (configurable)
Double tap to wake               Working    pro1x-doubletap (configurable)
Suspend                          Untested
GPS                              Not yet    modem's location service gives no NMEA (see TODO.md)
NFC, video codecs                Untested
Full-disk encryption             Untested   systems/mobile-encrypted.scm + flash-encrypted.sh
```

## Layout

```
modules/                     The channel's Guile modules (.guix-channel: directory)
modules/fxtec-pro1x/packages/  kernel, u-boot, firmware, audio, misc, sxmo
modules/fxtec-pro1x/services/  Shepherd services: audio, boot, camera, channels,
                             fde, hardware, keyboard, modem, sensors, usb-network
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

**Pre-built artifacts** (rootfs.img, and u-boot-nodtb.bin plus the DTB when
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
copy the two starting files the phone ships into `~/.config/guix/` and
edit them there:

```sh
cp /etc/guix/config.scm /etc/guix/channels.scm ~/.config/guix/
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

New accounts get Guix's default skeleton: `~/.bash_profile` and
`~/guix-home-config.scm`, but no `~/.bashrc`.  That is Guix's choice, not
a missing file: `guix-home-config.scm` is a ready Guix Home configuration
in which you uncomment the shell you use (Bash, Fish or Zsh); `guix home
reconfigure ~/guix-home-config.scm` then writes that shell's files, a
`~/.bashrc` included for Bash.  `~/.bash_profile` already loads the
profile from your latest `guix pull` (through `/etc/profile`): you do not
need to add it by hand.

### Home services from this channel (plan, not in place yet)

Guix manages two things separately: the **system** (kernel, drivers, system
services; `guix system reconfigure`) and your **home** (your programs'
settings in `~/.config`, and programs that run for you, such as the sound
server or notifications; `guix home reconfigure`).  Both are written in a
Scheme file, both can be rolled back.

This channel will provide ready-made home pieces for the Pro¹x: the sway
session and its bar, sound (PipeWire), and later mpv.  How you get them:

- **Do nothing.**  The default image sets up the home of the `user` account
  with the Pro¹x defaults.  Each system update (new image, `deploy.sh`) also
  updates them.
- **Use your own home config.**  If you already describe your home with Guix
  Home, add the Pro¹x pieces to it and keep the rest yours.  A sketch (names
  are not final):

  ```scheme
  ;; ~/home.scm -- apply with: guix home reconfigure ~/home.scm
  (use-modules (gnu home)
               (gnu home services)
               (fxtec-pro1x home))          ; this channel

  (home-environment
    (packages (list htop))                 ; your own programs
    (services
     (append
      (list
       ;; Pro¹x sway, bar and sound, with one change of your own:
       (service pro1x-home-sway-service-type
                (pro1x-home-sway-configuration
                 (extra-config "bindsym $mod+b exec icecat")))
       (service pro1x-home-audio-service-type))
      %base-home-services)))
  ```

Files managed this way are links into the store, so you change them in the
Scheme file and run `guix home reconfigure`, not by editing `~/.config`.
Until this is in place, the image puts the sway and bar configs in
`~/.config` once, for new accounts, and you edit them there.

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
  device-specific: kernel build, firmware, U-Boot, and the Pro¹x services.

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

## Keyboard

Layout: US international (`us` + `intl`).  The keys that differ from a PC
keyboard are remapped by keyd (`device/input/keyd.conf`), after the Pro1
keymap from droidian-devices/linux-android-fxtec-pro1 PR #2:

```
 Base layer: what each key types (keyd, then us-intl)
 ─────────────────────────────────────────────────────────────────────
  esc  1    2    3    4    5    6    7    8    9    0    -    =    bspc
  tab  q    w    e    r    t    y    u    i    o    p    [    ]    del
    caps a    s    d    f    g    h    j    k    l    ;    '    ret
  sft  `~   z    x    c    v    b    n    m    ,    .    /    up   sft
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
        so fx+Sym+letter types é, ñ, … on us-intl
  ; \ |  on fx+l, fx+p, fx+/ as on the yellow keycaps
  `~    sends 102nd, remapped to ` (Shift: ~; dead keys on us-intl)
  wlan, bt   rfkill keys for Wi-Fi and Bluetooth
  bri-, bri+, vol-, vol+, play, mute   screen brightness, volume, media

 Sway (Super = yellow arrow)
 ─────────────────────────────────────────────────────────────────────
  Super+Return                terminal (foot)
  Super+m                     application launcher
  Super+Tab                   window switcher
  Super+BackSpace, Super+Shift+q   close window
  Super+1…0, Super+Shift+1…0  go to / move to workspace
  Super+h j k l, Super+arrows focus; with Shift: move
  Super+f, Super+Shift+space  fullscreen, floating
  Super+r                     resize mode
  Super+Ctrl+h                show all sway key bindings
  Super+Shift+c, Super+Shift+e   reload sway, exit sway
  Power key                   panel off / on
```

`keyd monitor` (as root) shows what each key sends.

The keyboard backlight is on while the keyboard is slid out and the screen
is on (service `pro1x-kbd-backlight`).  Sliding the keyboard out with the
screen off turns the screen on in sway (not yet in Phosh).  To switch the
light by hand: `brightnessctl -d white:kbd_backlight set 0` (or `1`); it
stays that way until the next slide or screen change.

## Session selection

`systems/mobile.scm` boots into a **greetd + tuigreet** session picker on VT1.
tuigreet remembers the last user and each user's last session.  Three
sessions are offered, in this order:

| Session | Description |
|---|---|
| **1 Sway** | sway with `~/.config/sway/config` (device settings in `/etc/sway/config.d/pro1x.conf`) |
| **2 Phosh** | phoc-pro1x compositor + phosh-pro1x shell |
| **3 Sxmo + Sway** | Sxmo on sway, same device settings; needs superd (not packaged yet) |

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
