# Release notes

## 0.1.3 — 2026-10-29

- A configuration to start from on the phone: `/etc/guix/config.scm`
  inherits the port's system from the channel (new module
  `(fxtec-pro1x system mobile)`, procedure
  `pro1x-mobile-operating-system`), so `guix pull` still brings the
  port's changes to a customised system.  It lists root's SSH keys
  inline, with what they are for (`guix deploy` from a PC) and how to
  drop them.  See README "Your system configuration".
- `systems/mobile.scm` only adds the key from `keys/pro1x-guix.pub`;
  the system it builds is unchanged apart from that file.
- The minimal and encrypted systems still define everything themselves.

## 0.1.2 — 2026-10-29

- CI can publish releases: the release step was refused ("Resource not
  accessible by integration") because the workflow did not ask for
  `contents: write`; 0.1.0 and 0.1.1 have tags but no GitHub release.
  Otherwise the same as 0.1.1.

## 0.1.1 — 2026-10-29

- The channel can be pulled: `guix pull` failed to build it, because
  Guix compiles every `.scm` file in a channel's directory and the
  repository also holds scripts and system files.  The modules now live
  under `modules/` (`.guix-channel`: `(directory "modules")`); in a
  checkout, use `-L modules` instead of `-L .`.  The kernel module no
  longer uses `current-filename`, which is unset when Guix builds a
  channel.  Built systems are unchanged (same derivations as 0.1.0).
- The U-Boot "previous generation" entries are refreshed whenever
  `extlinux.conf` changes (deploy, reconfigure, delete-generations,
  roll-back, switch-generation), no longer only at boot.  Not tested on
  the phone yet.
- Keymap: Sym types `\` and `|`; Fn+l, Fn+p, Fn+/ give `;`, `\`, `|`.

## 0.1.0 — 2026-10-29

First release of GNU Guix System for the F(x)tec Pro¹x (QX1050,
SM6115): a near-mainline Linux 7.1 kernel, U-Boot chainloaded from the
stock bootloader, and a Guix userspace with Shepherd.  No vendor kernel,
no libhybris, no halium.

Built with guix 8b96d76 and nonguix c241d19 (`channels-lock.scm`).  This
is a developer preview: the phone boots to a usable graphical session,
but calls, audio and the cameras do not work yet.

### Install

Follow README "Flashing (first install)": back up the stock partitions,
unlock the bootloader, then `scripts/flash.sh`.  The release assets are
built by CI from `systems/mobile.scm`:

- `rootfs.img` — the root file system (grows to the whole userdata
  partition on first boot);
- `u-boot-nodtb.bin` and `sm6115-fxtec-pro1x.dtb` — present only if the
  CI U-Boot build succeeded; otherwise `scripts/flash.sh` builds U-Boot
  locally (needs Guix).

Log in as `user`, password `123456`; change it.  Release images carry no
root SSH key: `scripts/deploy.sh` needs your own key in `keys/` and an
image or generation built with it.

### Works (tested on the phone)

- Boot through U-Boot and extlinux; earlier generations in the boot menu
  (hold volume-down at power-on); A/B slot marking.
- `guix system delete-generations`, `roll-back` and `switch-generation`
  on the phone (for generations from this release on); run
  `sudo herd start pro1x-boot-menu` afterwards to refresh the U-Boot
  menu.
- Updates without reflashing: `scripts/deploy.sh` (guix deploy over USB
  Ethernet).
- Display (60 Hz), touch, landscape console with a Dracula palette.
- Hardware keyboard with an Fn layer (keymap in the README); keyboard
  backlight on while slid out and the screen is on.
- Wi-Fi (NetworkManager), USB Ethernet with SSH, clock set by NTP.
- greetd + tuigreet with Phosh, Sway and Sxmo sessions.
- Phosh: lock screen, home bar and app drawer, Phosh Mobile Settings and
  GNOME Settings, power key blanks and wakes the screen.
- Sway: bar, launcher, window switcher; sliding the keyboard out wakes
  the screen.
- ModemManager detects the modem (SIM, calls, SMS and data untested).

### Does not work yet

- Audio and cameras: PipeWire and WirePlumber are not set up (the
  camera sensors are detected; cameractrl shows black).
- Mobile network: no LTE network with a SIM inserted; calls, SMS and
  data untested.
- Sensors (auto-rotate, proximity): the ADSP sensor process crashes at
  boot.
- Phosh: brightness slider (needs logind), on-screen keyboard, dark
  theme switch, battery information.
- The U-Boot menu offers only the three previous generations, and U-Boot
  refuses kernel command lines over 511 bytes; recovery from a
  generation that does not boot can need U-Boot USB mass storage and a
  PC (see TODO.md).
- Full-disk encryption (`systems/mobile-encrypted.scm`): untested.

See TODO.md for the details and the plan.
