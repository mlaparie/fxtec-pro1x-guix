# Release notes

## 0.1.1 — 2026-10-31

0.1.0 was tagged but never published: its root file system was over
GitHub's 2 GiB limit for release files.  0.1.1 is the same system with the
image compressed (`rootfs.img.zst`).

First release of GNU Guix System for the F(x)tec Pro¹x (QX1050,
SM6115): a near-mainline Linux 7.1 kernel, U-Boot chainloaded from the
stock bootloader, and a Guix userspace with Shepherd.  No vendor kernel,
no libhybris, no halium.

Built with guix 8b96d76 and nonguix c241d19 (`channels-lock.scm`).  A
developer preview that works as a phone: calls, SMS and MMS, mobile
data, audio, cameras and sensors work; rough edges remain (below).

### Install

Follow README "Flashing (first install)": back up the stock partitions,
unlock the bootloader, then `scripts/flash.sh`.  The release assets are
built by CI from `systems/mobile.scm`:

- `rootfs.img.zst` — the root file system, compressed: `zstd -d
  rootfs.img.zst` gives `rootfs.img` (it grows to the whole userdata
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

- Hardware: display, touch, GPU; keyboard with an Fn layer and
  backlight; Wi-Fi; Bluetooth (audio too); USB Ethernet with SSH;
  speaker, earpiece, microphones; both cameras (Snapshot, early);
  accelerometer and proximity sensor; battery and charge limit;
  vibration; notification LED.
- Phone: SIM with PIN, calls (earpiece), SMS, MMS, mobile data.
- Sessions at the text login: Phosh, Sway made for the phone (edge
  swipes, quick actions, on-screen keyboard, lock screen with a touch
  keyboard), Sxmo (starts; needs superd).
- Updates without reflashing: `scripts/deploy.sh`, or `guix pull` and
  `guix system reconfigure` on the phone; earlier generations in the boot
  menu (hold volume-down at power-on).

The full list: [docs/features.md](docs/features.md).

### Does not work yet

- LTE not confirmed, GPS, speakerphone and mute in calls, headphones,
  light sensor, suspend.
- The U-Boot menu offers only the three previous generations, and U-Boot
  refuses kernel command lines over 511 bytes; recovery from a
  generation that does not boot can need U-Boot USB mass storage and a
  PC (see TODO.md).
- Full-disk encryption (`systems/mobile-encrypted.scm`): untested.

See TODO.md for the details and the plan.
