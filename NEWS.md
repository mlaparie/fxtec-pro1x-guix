# Release notes

## 0.1.0 — not released yet

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
root SSH key: `scripts/deploy.sh` needs an image built by
`scripts/flash.sh`, which makes the key (`~/.ssh/pro1x-guix`).

To customise the system, copy `/etc/guix/config.scm` and
`/etc/guix/channels.scm` to `~/.config/guix/` on the phone (README, "Your
system configuration"): the configuration inherits the port's system
from the channel, and root SSH for deploys is opt-in there.

### Works (tested on the phone)

- Boot through U-Boot and extlinux; earlier generations in the boot menu
  (hold volume-down at power-on); A/B slot marking.
- `guix pull` of this channel, and `guix system reconfigure` on the
  phone from `/etc/guix/config.scm`.
- `guix system delete-generations`, `roll-back` and `switch-generation`
  on the phone; the U-Boot "previous generation" entries follow every
  change of the boot menu (refresh on each change: not tested yet).
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
