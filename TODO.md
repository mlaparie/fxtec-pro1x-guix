# Status & remaining work

Last verified: 2026-10-27, on image built from commit a655fdf.

---

## Working

- **Boot chain**: U-Boot + extlinux, A/B slot success marking, boot menu (prev1…3)
- **Kernel**: linux-pro1x booting, all expected modules loaded
- **USB networking**: usb0 (RNDIS/g_cdc), 172.16.42.1, SSH access
- **WiFi**: ath10k_snoc driver working, NetworkManager connects (verified: Livebox-9416, IPv4+IPv6)
- **Audio hardware**: `/proc/asound/cards` shows `Pro1X` (sm4250); UCM2 paths set up, pro1x-audio-init ran
- **Camera hardware**: qcom_camss, imx582, s5k4h7, dw9800 modules loaded
- **Modem firmware services**: rmtfs, tqftpserv, pro1x-hexagonrpcd all running
- **elogind**: running (pid 519)
- **D-Bus system**: running
- **Rootfs resize**: one-shot ran at boot
- **NetworkManager**: running (nmcli works, confirmed via D-Bus; not visible in `herd status` — likely D-Bus-activated)

---

## 1. Phosh / display  [HIGH — TTY only, no GUI]

**Symptom**: phosh shepherd service stops immediately after starting:
```
[backend/session/session.c] Failed to load session backend
[backend/backend.c] Failed to start a session
[backend/backend.c] Failed to start a DRM session
```
`/dev/dri/card0` and `renderD128` exist, so DRM hardware is fine.
elogind IS running, but the phoc start script uses `su -l user` from shepherd
(root), which does not go through PAM and therefore does not create an elogind
seat session — libseat finds no usable backend and fails.

**Fix options**:
1. Add `seatd-service-type` and put `user` in the `seat` group — libseat will use
   the seatd socket instead of elogind, no PAM session needed.  This is the
   standard approach for Wayland compositors under Guix/shepherd.
2. Replace the hand-rolled shepherd service with `greetd-service-type` — greetd
   creates proper PAM sessions before exec-ing the compositor.

Option 1 is the simpler path.

---

## 2. PipeWire / audio daemon  [HIGH — audio hardware detected but silent]

Audio hardware is initialised (ALSA card present, pro1x-audio-init ran).
Missing: the PipeWire daemon, WirePlumber session manager, PipeWire-Pulse
bridge, and rtkit for real-time scheduling.

NixOS reference:
```nix
services.pipewire.enable = true;
services.pipewire.alsa.enable = true;
services.pipewire.pulse.enable = true;
services.pipewire.wireplumber.enable = true;
security.rtkit.enable = true;
```

**Fix**: extend `pro1x-audio-service-type` or `systems/mobile.scm` to start
`pipewire`, `pipewire-pulse`, and `wireplumber` as per-user Shepherd services
(or system-wide), and add the `rtkit` daemon.  Packages: `pipewire` in
`(gnu packages pulseaudio)`, `rtkit` in `(gnu packages realtime)`.

---

## 3. dconf profiles / keyboard layout  [MEDIUM — layout lost on reboot]

NixOS persists the physical keyboard XKB layout via a dconf profile.  Guix
only ships `gsettings-desktop-schemas` (prevents crash); no dconf db is written
so the layout reverts to default after every boot.

**Fix**: write `/etc/dconf/profile/user` and `/etc/dconf/db/local.d/` via
`etc-service-type`, run `dconf update` in a one-shot service.  Generate the
xkb settings from `pro1x-keyboard-configuration` fields.

---

## 4. ModemManager exits immediately  [MEDIUM — modem/calls broken]

ModemManager shepherd service exits with code 0 five times at boot (~01:51:04)
and is then disabled.  No log file is created (exits before writing anything).
rmtfs, tqftpserv, and hexagonrpcd are all running when MM starts.

**Investigate**: start MM manually (`sudo ModemManager --debug`) to capture
its startup output.  Likely causes: missing D-Bus policy, missing firmware,
or a missing group/udev rule.

---

## 5. iio-sensor-proxy  [LOW — no auto-rotate]

`iio-sensor-proxy` is not registered in Shepherd.  `pro1x-sensors-service-type`
extends `dbus-root-service-type` but the D-Bus `.service` file for auto-activation
may be missing, so the daemon is never started.

**Fix**: verify `iio-sensor-proxy.service` is in the D-Bus system services
directory, or add it as an `etc-service-type` entry.

---

## 6. ModemManager `wants` dependency  [LOW — race condition risk]

Shepherd `requirement` is equivalent to `After=` but not `Wants=` — if rmtfs
is not already running, ModemManager refuses to start rather than triggering
it.  Currently `pro1x-modem-service-type` declares all three together so this
should be fine in practice, but worth confirming once MM startup is fixed.

---

## 7. NTP clock stepping from 1970  [LOW — fixed in next build]

`openntpd` uses `adjtime()` which rejects the ~56-year offset from 1970.
Replaced with `ntp-service-type` + `(allow-large-adjustment? #t)` which passes
`-g` to ntpd, allowing an unconditional clock step.  Will take effect after
next flash.

---

## 8. GitHub CI  [VERIFY — last known good: a655fdf push]

CI was failing due to glib graft on cached read-only store path (`--no-grafts`
fixed), `/tmp` mount inheritance (daemon restart order fixed), and gitconfig
permissions.  Latest fixes are in `.github/workflows/build.yml`.

Verify: confirm the CI run triggered by the most recent push is green end-to-end.

---

## Resolved

- **§ tqftpserv firmware path**: fixed — `modem.scm` creates the symlink at
  service-start time by reading `firmware_class.path` from sysfs.
- **§ u-boot-pro1x build**: fixed — ARM64 `text_offset` zeroed so ABL accepts
  the image; vbmeta flags offset corrected; phone boots into U-Boot.
- **§ emacs / nnn / mpv**: added to system packages.
- **§ rootfs too small**: `pro1x-rootfs-resize-service-type` expands the ext4
  filesystem to fill the partition on first boot.
- **§ NM connections not writable**: NM keyfile path redirected to
  `/var/lib/NetworkManager/system-connections/`.
