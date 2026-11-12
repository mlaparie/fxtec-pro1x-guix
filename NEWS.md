# Release notes

## 0.5.0 — 2026-11-12

Fingerprint unlock in Sway and Phosh, Android apps with Waydroid, and
Log out back to the greeter.  Built with guix 8b96d76 and nonguix c241d19.

### New

- Fingerprint reader: enrol in quick actions (Sway) or GNOME Settings
  (Phosh, through an fprintd-compatible service), unlock either lock screen
  by finger.  The sensor is read only while the lock screen is up and lit
  (about 15 % of one core meanwhile).  A rejected touch says why (partial
  touch, same spot as before, finger already enrolled).
- Waydroid 1.6.3 (after phodina's Guix series): LineageOS 20 in a
  container, with or without Google Play.  Quick actions' Waydroid menu
  downloads the image, starts, freezes, resumes and stops Android, shows
  its apps, installs APKs, sets one window or one per app and "Sleep when
  unused", and shows the ID Google asks for.  Its notifications reach the
  desktop.  config.scm: `waydroid-configuration` `autostart?`.
- Log out back to tuigreet, from Sway's power menu and Phosh's top panel.
- The btrfs root comes compressed from CI again (btrfs-progs with the fix
  for kdave/btrfs-progs#1135); no compression at first boot.
- Quick actions: Auto-sleep (1 to 60 minutes locked); notifications newest
  first, with the time they came.
- `backup-phone.sh` asks whether to save Waydroid (its apps and accounts,
  or the image too).
- Kernel: moWerk's three QSEECOM fixes, for the fingerprint trusted app.

### Install

Download the `rootfs.img.zst.part*` files and `SHA256SUMS`, check them
with `sha256sum -c SHA256SUMS`, join and unpack with
`cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, then follow
docs/install.md (`scripts/flash.sh --encrypt --rootfs rootfs.img`).

### Known issues

- Outgoing calls on 4G often fall back to 3G and take 20-40 s to ring.
- Mute in calls has no effect; no echo cancelling.
- Waydroid: Super opens Google's Assistant while an Android window has the
  focus; Android's first boot takes about 2 minutes and keeps two cores busy
  for a while.
- A 5 GHz hotspot is impossible (the Wi-Fi chip's regulatory domain).
- Wi-Fi takes about 100 s to connect after a boot.

## 0.4.0 — 2026-11-11

A btrfs root with snapshots of `/home`, a Stream menu to send the screen to
another device, a Wi-Fi hotspot, and many quick actions.  Built with guix
8b96d76 and nonguix c241d19.

### New

- btrfs root by default, zstd-compressed, `/home` a subvolume with btrbk
  snapshots (hourly when it changed, 1 day of all, 7 daily, 3 weekly).
  The image is written uncompressed and compressed once at first boot
  (CI's aarch64 `mkfs.btrfs --compress` wrote extents the kernel could not
  read).  Only `flash.sh --encrypt` takes it for now.
- Stream (quick actions): the screen or a window to VLC over UDP, to a
  browser over WebRTC (H.264 or VP8), as MJPEG, to a Chromecast (catt), or
  mirrored with Network Displays.  Hardware H.264 (Venus) beside the software
  encoders; Capture rate and Output size settings.
- Hotspot (quick actions): QR code, band, hidden name, auto-off when idle,
  data used, connected devices with expel and ban, and streaming to one.
- Quick actions: Wi-Fi networks, Timezone (from the cell network, then the
  IP), Audio output (several at once), all as sublists with a back line;
  airplane mode as a real state.
- XWayland for apps without a Wayland mode; Caps Lock is the Compose key; a
  font for Chinese, Japanese and Korean; wireless-regdb.
- Keyboard: a key pressed during the last scan is no longer lost.
- Guix Home in its own file (`home.scm`), deployed with `deploy.sh --home`.
- Kernel: RPM vmin in suspend (moWerk's 0050, 0051, 0056); UHID and the Elecom
  driver for Bluetooth LE mice; the keyboard backlight on at boot, for the
  passphrase prompt.
- Modem: XTRA orbit data kept fresh; GNSS engine unlocked at every boot;
  Satellite, a GPS app.
- `backup-phone.sh` also saves the `guix install` packages and the clock
  offset; `PRO1X_EXCLUDE` leaves paths out of the home.
- Fingerprint reader: the trusted app answers (chip id 0x24) through the
  QSEECOM driver; no enrolment or unlock yet.

### Install

Download the `rootfs.img.zst.part*` files and `SHA256SUMS`, check them
with `sha256sum -c SHA256SUMS`, join and unpack with
`cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, then follow
docs/install.md (`scripts/flash.sh --encrypt --rootfs rootfs.img`).

### Known issues

- Outgoing calls on 4G often fall back to 3G and take 20-40 s to ring.
- Mute in calls has no effect; no echo cancelling.
- A 5 GHz hotspot is impossible (the Wi-Fi chip's regulatory domain).
- Wi-Fi takes about 100 s to connect after a boot.

## 0.3.0 — 2026-11-06

0.2.0 was tagged but its release never got its root file system (over
GitHub's 2 GiB limit even compressed); 0.3.0 has it, in parts.  Built
with guix 8b96d76 and nonguix c241d19.

### New

- Full-disk encryption flashed on a phone: `flash.sh --encrypt` sends
  `userdata` as sparse parts (Guix's fastboot sent an empty image), and
  the boot menu keeps the plain area up to date.  A passphrase may have
  symbols (US layout at the prompt).
- `scripts/backup-phone.sh`: the phone's data (home, Wi-Fi, Bluetooth,
  Tailscale, SSH host keys) to the PC before a reflash, and back after
  (docs/install.md).
- Stronger vibration for calls and texts; `vibration-level` in
  `config.scm` (default 80, stock 59).  Shake to torch needs a firmer
  shake.
- Sway: menus slide in from their swipe's side; windows open and close
  with a 200 ms animation; inactive windows dimmed slightly.
- Volume keys and quick actions' volume: a step takes 30-150 ms, not
  300 ms.
- nvtop (GPU monitor) from quick actions' GPU line.
- Esc to wake no longer opens the power menu.
- U-Boot menu: "Reboot to fastboot (stock bootloader)" replaces
  U-Boot's own fastboot, which cannot write this phone's UFS (not yet
  tried on the phone).
- docs/usage.md: Sway's menus and keys, passwords.

### Removed

- The plain Sway session (for comparing speed); the FDE prompt test;
  the 7.1 kernel patches (tag `pre-7.3` has them).

### Install

Download the `rootfs.img.zst.part*` files and `SHA256SUMS`, check them
with `sha256sum -c SHA256SUMS`, join and unpack with
`cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, then follow
docs/install.md (`scripts/flash.sh --rootfs rootfs.img`, with
`--encrypt` for an encrypted phone).

### Known issues

- Outgoing calls on 4G often fall back to 3G and take 20-40 s to ring.
- Mute in calls has no effect; no echo cancelling.
- Charging goes above the charge limit; no deep sleep.

## 0.2.0 — 2026-11-05

Linux 7.3 (mainline, moWerk's series and this port's patches), calls on
4G through VoLTE, optional full-disk encryption, and a Sway session made
for the phone.  Built with guix 8b96d76 and nonguix c241d19.

### New

- VoLTE: 81voltd (postmarketOS) serves the IMS data connection the modem
  asks for, and a watchdog restarts it when 4G has none.  On Free in
  France, incoming calls on 4G rang 8 times in 8 with it, against about
  one in three without.  Outgoing calls connect, but most take 20–40 s
  on 4G: the modem falls back to 3G (one in five rang within 2 s).
- Call audio on 7.3: both ways, earpiece and speaker, volume keys in
  calls.
- Full-disk encryption (LUKS2), asked for by `scripts/flash.sh`, also
  with a CI `rootfs.img`: tested in QEMU and with the phone's prompt, not
  yet flashed on a phone.
- U-Boot menu with generation numbers and dates, the current one and four
  older; countdown in `config.scm`.
- Sway: lock screen (gtklock, black, follows rotation), quick actions
  (operator choice with automatic fallback, charge limit, CPU mode,
  notifications), edge swipes, SIM PIN prompt at login, on-screen keyboard
  on demand.
- `nm-connection-editor` for Wi-Fi settings beyond nmtui (WPA2
  Enterprise).
- `config.scm` lists every option of the port's services.
- nvtop, a GPU monitor, opened from the quick actions' GPU line.

### Install

As for 0.1.1 (below), except that the root file system comes in parts,
since even compressed it is over GitHub's 2 GiB limit:
`cat rootfs.img.zst.part* | zstd -d -o rootfs.img`, after checking them
with `sha256sum -c SHA256SUMS`.

### Known issues

- Mute in calls has no effect; no echo cancelling; the microphone picks up
  handling noise.
- One VoLTE call in eight had no sound (not reproduced).
- Charging goes above the charge limit; suspend does not reach the SoC's
  deep sleep.
- The boot menu's labels are stale while a generation older than
  2026-11-04 runs.
- A reflash drops every earlier generation.

## 0.1.1 — 2026-10-31

0.1.0 was tagged but never published: its root file system was over
GitHub's 2 GiB limit for release files.  0.1.1 is the same system with the
image compressed (`rootfs.img.zst`), which was still over the limit: its
release has U-Boot and the DTB but no root file system (the CI build's
artifact has it).

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
