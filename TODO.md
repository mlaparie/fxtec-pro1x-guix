# Status & remaining work

Last verified: 2026-10-27, on image built from commit a655fdf.
Phone survey 2026-10-28 on the image from **6b37ac4** (inferred: generation 1
built 2026-10-27 13:02 UTC, Guix 5ceffb6; qrcodegen-cpp present, cameractrl
4c8ac34, no greetd).  Results are in §4, §7, §12, §13.

**Reference repos** (Claude may clone these to /tmp at any time):
- NixOS port (almost fully working, authoritative hardware reference):
  `git clone https://github.com/nyymi609/fxtec-pro1x-nixos /tmp/fxtec-pro1x-nixos`
- Guix source + manual:
  `git clone https://codeberg.org/guix/guix /tmp/guix`

The NixOS `device/` directory is explicitly distro-agnostic (README §Other distros):
> Apply the kernel patches and config, install `device/audio/ucm2` into
> alsa-ucm-conf, run `pro1x-audio-init` at boot, and use
> `device/input/keyd.conf` and `device/udev/60-pro1x.rules`.

---

## Next steps (plan, 2026-10-28)

The sections below were last checked on a655fdf; about 40 commits have
landed since (phosh 0.56, MM 1.24, seatd, Sxmo/greetd, ntp -g), none
verified on the device.  Order:

1. **Re-verify on the device.** Flash the image from the current local
   build, go through every section here, update or close it.  Needs the
   author once (flash).
2. **Deploy without reflashing (§10), then bootcount fallback (§11).**
   `scripts/deploy.sh` (guix deploy) works (2026-10-28, generation 3);
   reboot into a deployed generation not tested yet.
   Then each later step is one generation the agent can deploy and roll
   back alone.
3. **Phosh session + keyboard layout (§1, §3).** Phosh from tuigreet
   fails, sway works (author, 2026-10-28); generation 5 logs the Phosh
   session to /tmp/phosh-UID.log.  Phosh starting from greetd,
   the layout surviving a reboot.
4. **Guix Home layer, then audio (§2).**  Home services in the channel
   (`fxtec-pro1x home ...`): sway session, i3status-rust, mako/swayidle as
   user services, later mpv.  The default image applies a home environment
   for `user` through `guix-home-service-type`; these replace the
   skeletons, so updates reach existing homes.  Audio through the same
   layer: `home-pipewire-service-type` (PipeWire, pipewire-pulse,
   WirePlumber) + `home-dbus-service-type`, rtkit, `pro1x-audio-init`
   before WirePlumber, merged UCM2 tree.  Playback on speaker and headset
   first.  README "Your home configuration" describes the intended use.
5. **Modem (§4, §6).** MM up and seeing the modem, SIM provisioning; SMS,
   calls and data only with the author's go-ahead each time.
6. **Voice-call audio.** q6voice patch is in the kernel; userspace
   `pro1x-voice-call`/`voicepcm` from NixOS still to translate.
7. **Sensors (§5).** Mount-matrix and SSC udev rules, wait for QRTR 400.
8. **CI green (§9), artifact size (§8).**
7b. **Redo the dpugap/panelgap sync with the NixOS port** (69697e4,
   reverted in 9f1e7c8 to reuse the built kernel).  Cosmetic only; redo it
   with the next real kernel change, so the kernel is rebuilt once.
8a. **Video decode (Venus):** no hardware codec yet.  Firmware and driver
   (QCM2290 AR50 Lite) are there; needs an SM6115 video-codec DT node
   (rag-notes hardware.json "video").  Then mpv --hwdec=v4l2m2m-copy,
   shipped as a home skeleton (~/.config/mpv/mpv.conf) like the sway
   configs.  VA-API/libva does not apply to Venus.  Low priority: only
   helps mpv/FFmpeg/GStreamer, not IceCat (2026-10-28 discussion).
8b. **Sway extras, when wanted:** more scripts from mlaparie's guix-config
   (nmcli-fzf for Wi-Fi as a bar click, power menu, clamshell mode), and
   i3status-rust click actions.  Strip PC-specific parts first.
9. **Not yet surveyed:** battery/charging reporting, suspend, haptics and
   LED (feedbackd), GPS, camera userspace, backlight.  Keyboard backlight:
   pro1x-kbd-backlight: LED follows slide in/out and the power key
   (generation 4, author).  Generation 5 (850ca36): slide-out wakes the
   panel in sway, not tested; Phosh not handled.  Compare each with
   the NixOS port before planning.
10. **Updates for users** (README, "Updates in the long run"): a
    substitute server for this channel's aarch64 builds, fed by CI, and
    releases that pin Guix and nonguix commits.  After the port is usable
    day to day; the CI build cache (bc8c7cf) is a first step.
11. **Upstreaming candidates** (author's review first): libqmi 1.36,
    ModemManager 1.24, phosh 0.56, feedbackd, callaudiod to Guix;
    firmware-dependent parts stay here or go to nonguix.

---

## Working

- **Boot chain**: U-Boot + extlinux, A/B slot success marking (boot menu prev1…3: never exercised, offset fixed in f737b70, §13)
- **Kernel**: linux-pro1x booting, all expected modules loaded
- **USB networking**: usb0 (RNDIS/g_cdc), 172.16.42.1, SSH access
- **WiFi**: ath10k_snoc driver working, NetworkManager connects (verified on home Wi-Fi, IPv4+IPv6)
- **Audio hardware**: `/proc/asound/cards` shows `Pro1X` (sm4250); UCM2 paths set up, pro1x-audio-init ran
- **Camera hardware**: qcom_camss, imx582, s5k4h7, dw9800 modules loaded
- **Modem firmware services**: rmtfs, tqftpserv, pro1x-hexagonrpcd all running
- **elogind**: running (pid 519)
- **D-Bus system**: running
- **Rootfs resize**: one-shot ran at boot
- **NetworkManager**: running (nmcli works; not visible in `herd status` — D-Bus activated)

---

## 1. Phosh / display  [HIGH — TTY only, no GUI]

**Symptom**: phosh shepherd service stops immediately:
```
[backend/session/session.c] Failed to load session backend
[backend/backend.c] Failed to start a DRM session
```
`/dev/dri/card0` and `renderD128` exist. elogind IS running.

**Root cause**: The phoc shepherd service uses `su -l user` from root, which
does not create a PAM/logind session. libseat finds no usable session backend.

NixOS uses `services.xserver.desktopManager.phosh` which starts through
systemd-logind (which implicitly creates a seat session). On Guix without
systemd, the equivalent is `seatd`.

**Fix**: Add `seatd-service-type` (from `(gnu services desktop)`; seatd is a
minimal seat management daemon that doesn't require PAM sessions).  Add `user`
to the `seat` group.  libseat will then use the seatd Unix socket instead of
trying to talk to elogind.  No PAM change needed in the shepherd service.

NixOS phoc config reference:
```nix
services.xserver.desktopManager.phosh = {
  enable = true;
  user = "nixos";
  group = "users";
  phocConfig.outputs.DSI-1.scale = 2;
};
```

---

## 2. PipeWire / audio daemon  [HIGH — audio hardware detected but silent]

Audio hardware is initialised (ALSA card `Pro1X` present, pro1x-audio-init
one-shot ran).  Missing: PipeWire daemon, WirePlumber, PulseAudio bridge, rtkit.

**NixOS implementation** (`modules/audio.nix`):
```nix
services.pipewire = {
  enable = true;
  alsa.enable = true;
  pulse.enable = true;
  wireplumber = {
    enable = true;
    configPackages = [ audio ];           # Pro1X WirePlumber config
    serviceConfig.ExecStartPre = [ "${audio}/bin/pro1x-audio-init" ];
  };
};
security.rtkit.enable = true;
environment.variables.ALSA_CONFIG_UCM2 = ucmDir;  # merged UCM tree
```
WirePlumber runs `pro1x-audio-init` in ExecStartPre.  The UCM2 tree from
`device/audio/ucm2/` is merged into alsa-ucm-conf and pointed to by
`ALSA_CONFIG_UCM2`.  There is also a user service `pro1x-voicepcm` for voice
calls (started by UCM VoiceCall verb).

**Fix**: Extend `pro1x-audio-service-type` to start `pipewire`,
`pipewire-pulse`, and `wireplumber` as per-user Shepherd services.  Add the
`rtkit` daemon.  Run `pro1x-audio-init` before WirePlumber.
Packages: `pipewire` in `(gnu packages pulseaudio)`, `rtkit` in
`(gnu packages realtime)`.

---

## 3. dconf profiles / keyboard layout  [MEDIUM — layout lost on reboot]

NixOS (`hosts/phosh/default.nix`):
```nix
programs.dconf.enable = true;
programs.dconf.profiles.user.databases = [{
  settings."org/gnome/desktop/input-sources".sources = [
    (lib.gvariant.mkTuple [ "xkb" "fi+nodeadkeys" ])
  ];
}];
```

**Fix**: Write `/etc/dconf/profile/user` and `/etc/dconf/db/local.d/` via
`etc-service-type`, run `dconf update` in a one-shot service.  Generate the
xkb settings from `pro1x-keyboard-configuration` (already has `xkb-layout` /
`xkb-variant` fields).

---

## 4. ModemManager exits immediately  [MEDIUM — modem/calls broken — FIX IN NEXT BUILD]

**2026-10-28, image 6b37ac4:** MM 1.24.0 now starts and stays up (the D-Bus
fix works), probes qrtr0, then: `couldn't create modem for device
'qcom-soc': Failed to find a net port in the QMI modem`.  `rmnet_ipa0` has
no `ID_MM_*` properties: MM's own udev rules (`77-mm-qcom-soc.rules`) were
never given to udev, and neither was our `60-pro1x.rules` (§12).  Fixed in
`services/modem.scm` (udev extension with modem-manager-1.24); untested.

Older notes:

ModemManager shepherd service exited with code 0 five times at boot and was
then disabled.

**Root cause identified**: `pro1x-modem-service-type` was missing
`(service-extension dbus-root-service-type ...)`.  ModemManager's D-Bus policy
file was never loaded into dbus-daemon, so it could not claim
`org.freedesktop.ModemManager1` and exited cleanly.

**Fixed** in `fxtec-pro1x/services/modem.scm`: added the dbus-root-service-type
extension.  Will take effect after next flash.

NixOS has no explicit D-Bus config because `networking.modemmanager.enable`
installs everything (policy files, udev, polkit) automatically.  Guix needs to
wire it manually.

Also install `libqmi` and `qrtr` packages (NixOS: `environment.systemPackages
= [ libqmi qrtr ]`).

---

## 5. iio-sensor-proxy  [LOW — no auto-rotate]

**NixOS implementation** (`modules/sensors.nix`):
```nix
services.dbus.packages = [ pkgs.iio-sensor-proxy ];
services.udev.packages = [ pkgs.iio-sensor-proxy ];
systemd.packages = [ pkgs.iio-sensor-proxy ];  # D-Bus activated
services.udev.extraRules = ''
  SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp", \
    ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity"
  SUBSYSTEM=="misc", KERNEL=="fastrpc-*", \
    ENV{ACCEL_MOUNT_MATRIX}+="-1, 0, 0; 0, -1, 0; 0, 0, 1"
'';
# iio-sensor-proxy ExecStartPre: wait 60 s for QRTR service 400 (SSC)
# pro1x-hexagonrpcd ExecStartPre: wait 240 s for /dev/fastrpc-adsp
```

`pro1x-sensors-service-type` already extends `dbus-root-service-type` and
`udev-service-type`, but the mount matrix udev rule and the QRTR 400 wait in
iio-sensor-proxy's startup may be missing.

**Fix**: Add udev rules for `ACCEL_MOUNT_MATRIX` and `IIO_SENSOR_PROXY_TYPE`
on `fastrpc-*` devices.  Add a wait loop for `qrtr-lookup | grep '^ *400 '`
(SSC sensor service) before starting iio-sensor-proxy.

---

## 6. ModemManager `wants` dependency  [LOW — verify after §4 fix]

Shepherd `requirement` is `After=` but not `Wants=`.  If rmtfs is not yet
running when MM starts, MM refuses rather than triggering rmtfs.  This is
currently moot because MM exits for other reasons; verify once §4 is fixed.

---

## 7. NTP clock stepping from 1970  [LOW — fixed in next build]

Replaced `openntpd-service-type` with `ntp-service-type` +
`(allow-large-adjustment? #t)`, which passes `-g` to ntpd allowing an
unconditional clock step.  Will take effect after next flash.

**2026-10-28, image 6b37ac4:** ntpd runs, Wi-Fi was up, yet `date` read
1970-01-01 21:50 one minute after boot.  Not followed further: check
`ntpq -p` and `/var/log/ntpd.log` a few minutes after boot.

---

## 8. CI artifact size  [LOW — check after next successful build]

The "2 GB per-file artifact limit" noted here earlier is the limit for
**Release** assets (2 GiB per file); no per-file limit was found for Actions
artifacts (`upload-artifact@v4`), only retention (≤ 90 days) and storage
quota (2026-10-28, third-party sources, not GitHub's docs).

CI now runs `resize2fs -M` on `rootfs.img` before upload (the phone grows it
back on first boot); it prints the size before and after.  Next, if needed:
`zstd` the image, upload with `compression-level: 0`, and teach `flash.sh`
to read `.zst`.  For Release assets, split under 2 GiB.

---

## 9. GitHub CI  [VERIFY — no green run yet]

CI was failing due to glib graft on cached store path (`--no-grafts` fixed),
`/tmp` mount inheritance (daemon restart order fixed), and gitconfig
permissions.  The earlier "last known good push: 64f123d" was wrong:
`gh run list -s success` shows no successful run among the last 40 (checked
2026-10-28).

Run 40702633350 (commit 018fa97) built every package and failed only in the
rootfs `partition.img` builder, with Guix's "lack of free disk space" note.
Cause (inferred, not measured): with `--disable-chroot` the daemon builds in
`$TMPDIR`, which was the 4G `/tmp` tmpfs; that builder stages the system
closure plus the ext4 image there.  Fix: the daemon's `TMPDIR` is now
`/var/tmp/guix-build` on the root disk; the failure branch now prints each
failed builder's log.  Verify on the next run.  The previous run (40599232782)
failed earlier, on webkitgtk.

---

## 10. Deploy without reflashing  [MEDIUM — works, reboot into a deployed generation not tested]

`scripts/update.sh` (NixOS commands, broken) and the NixOS `scripts/deploy.sh`
are replaced by `scripts/deploy.sh` → `guix deploy -L . deploy/pro1x.scm`:
build on the host, copy as root over SSH, new boot generation.  Root SSH by
key (`keys/pro1x-guix.pub`, `permit-root-login 'prohibit-password`) is in
all three `systems/*.scm`, and on the phone since the 2026-10-28 reflash.

First use 2026-10-28 (image flashed by the author; generation 1 built
2026-10-28 21:27, source commit not recorded):
- deploy 1 made generation 2 current but stopped before the bootloader:
  activation rewrote /etc/guix/acl without the host key.  Fixed in
  763f71a; deploy 2 (generation 3, the tree of 66f1456) succeeded and
  extlinux.conf lists generations 3, 2, 1;
- activation errors at every boot and deploy (NM mkdir EROFS, dconf
  update EROFS) fixed in 35703cb and 66f1456.  A deployed phone keeps
  the stale /etc/NetworkManager link: `rm /etc/NetworkManager` then
  reactivate (done on this phone);

- generation 4 (8e5e0a7): provenance lists only guix, nonguix and
  fxtec-pro1x at the deployed HEAD (dcb2dec); /etc/guix/channels.scm
  lists the same three (f666fd0), not pulled from yet.

- 2026-10-29: rebooting into generation 5 failed in the initrd ("ext4:
  unknown parameter 'noatime'"); generations 2-5 all share it, the
  U-Boot prev1-3 slots pointed at 4, 3, 2.  Recovered through U-Boot USB
  mass storage: generation 1 first in extlinux.conf (.bak kept).  Fixed
  in 3b1c86d (flags no-atime).  Generations 2-5 stay unbootable in the
  menu until the author decides to delete them.

Still to check:
- reboot into a deployed generation with 3b1c86d;
- the boot menu should always keep one generation known to boot (the
  prev slots only cover the 3 newest);
- U-Boot menu: TIMEOUT 100 in extlinux.conf, but the author saw no
  generation list on screen; the U-Boot bootmenu shows only Boot and
  prev1-3;
- whether the deploy copies only what changed (not measured);
- `prev*.conf` (boot-menu split, rewritten only at boot) still point at
  bootable generations between deploy and reboot;
- what `want=n+2` in `services/boot.scm` skips in extlinux.conf;
- encrypted system: `update-encrypted-boot.sh` still needed afterwards.

---

## 11. No boot-once / bootcount fallback  [LOW — safety]

A generation that changes the kernel, initrd or USB networking and does not
boot far enough for SSH can only be recovered by hand (volume-down boot
menu).  A boot-once or bootcount mechanism in U-Boot (fall back to the
previous generation after N failed boots, cleared by
`pro1x-boot-success-service-type`) would let those changes be tested
without the author at the device.  See AGENTS.md §3.

---

## 12. Our udev rules never reached udev  [HIGH — fixed, untested]

Seen on the phone: no `60-pro1x.rules` or `90-pro1x-sensors.rules` in
`/etc/udev/rules.d`.  `udev-service-type` extensions must be directories
with `lib/udev/rules.d/`; a bare rules file is dropped silently.  This cost
the rmnet tag (modem), haptics, slider, and the sensor mount-matrix/SSC
rules.  Fixed with `file->udev-rule` in `services/hardware.scm` and
`services/sensors.scm`; iio-sensor-proxy and ModemManager now also pass
their own rules.

## 13. Smaller things seen on the phone (image 6b37ac4)

- `cfg80211: failed to load regulatory.db` (no wireless-regdb).
- `qcom/a630_sqe.fw` fails in the initrd, loads at 11 s from the rootfs.
- `goodix_9286_cfg.bin` missing (touch uses its built-in config).
- `term-console` (agetty on ttyMSM0) exits 1 and respawns.
- `qrtr-lookup` not installed (needed for the sensors wait, §5).
- phosh service "started", phosh.log shows only "Session terminated".
- Boot menu: Guix extlinux.conf has no Default entry; split script fixed
  (f737b70), untested with more than one generation.
- Rootfs resize worked: 222G, 9.8G used.  Boot-slot marking works.

---

## Resolved

- **ModemManager D-Bus policy**: fixed in `services/modem.scm` — added
  `dbus-root-service-type` extension so MM's policy file is loaded.
- **tqftpserv firmware path**: fixed — `modem.scm` creates the symlink at
  service-start time by reading `firmware_class.path` from sysfs.
- **u-boot-pro1x build**: fixed — ARM64 `text_offset` zeroed so ABL accepts
  the image; vbmeta flags offset corrected.
- **emacs / nnn / mpv**: added to system packages.
- **rootfs too small**: `pro1x-rootfs-resize-service-type` expands ext4 on
  first boot.
- **NM connections not writable**: NM keyfile path redirected to
  `/var/lib/NetworkManager/system-connections/`.
