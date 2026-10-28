# Status & remaining work

Last verified: 2026-10-27, on image built from commit a655fdf.

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

---

## 8. CI artifact size  [LOW — check after next successful build]

GitHub Actions has a 2 GB per-file artifact limit.  The rootfs image may be
close to or over that with IceCat + calls + chatty added.  The CI log prints
`rootfs: N MiB` at the end of the image build step.

**If over ~1800 MiB**: add a `gzip -1 rootfs.img` step before the upload-artifact
step in `.github/workflows/build.yml`, and rename the artifact path to
`rootfs.img.gz`.  ext4 images compress well (~50 % reduction typical).

---

## 9. GitHub CI  [VERIFY — last known good push: 64f123d]

CI was failing due to glib graft on cached store path (`--no-grafts` fixed),
`/tmp` mount inheritance (daemon restart order fixed), and gitconfig
permissions.  Verify the CI run triggered by the latest push is green.

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
