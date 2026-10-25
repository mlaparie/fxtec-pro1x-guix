# Remaining work — NixOS parity

Reference: `/tmp/fxtec-pro1x-nixos/` (modules/hardware.nix, modules/audio.nix,
modules/modem.nix, modules/sensors.nix, hosts/*/default.nix)

---

## 1. PipeWire / audio stack  [HIGH — audio broken]

NixOS enables:
```nix
services.pipewire.enable = true;
services.pipewire.alsa.enable = true;
services.pipewire.pulse.enable = true;
services.pipewire.wireplumber.enable = true;
security.rtkit.enable = true;
```

Guix `pro1x-audio-service-type` sets up UCM2 paths, WirePlumber config, and an
audio-init one-shot, but does **not** start the PipeWire daemon itself, does not
enable the ALSA or PulseAudio bridges, and has no rtkit service.

**Fix**: extend `pro1x-audio-service-type` (or `systems/mobile.scm`) to start
`pipewire`, `pipewire-pulse`, and `wireplumber` as Shepherd services, and add the
`rtkit` daemon with the `audio` group realtime-scheduling rule.  The relevant Guix
packages are in `(gnu packages pulseaudio)` (`pipewire`) and
`(gnu packages realtime)` (`rtkit`).

---

## 2. dconf profiles / keyboard layout  [HIGH — layout lost on reboot]

NixOS (phosh/default.nix):
```nix
programs.dconf.enable = true;
programs.dconf.profiles.user.databases = [{
  settings."org/gnome/desktop/input-sources".sources = [
    (lib.gvariant.mkTuple [ "xkb" "fi+nodeadkeys" ])
  ];
}];
```

Guix only includes the `gsettings-desktop-schemas` package (fixes the crash) but
has no dconf profile, so the keyboard layout is not persisted.

**Fix**: write a dconf profile to `/etc/dconf/profile/user` and a database to
`/etc/dconf/db/local.d/` via `etc-service-type`, and run `dconf update` in a
one-shot Shepherd service after the etc files are in place.  The xkb layout should
come from `pro1x-keyboard-configuration` (already has `xkb-layout`/`xkb-variant`
fields) so the dconf db is generated from that config.

---

## 3. Firmware compression  [MEDIUM — modem/ADSP remoteproc may need uncompressed]

NixOS sets `firmwareCompression = "none"` so all firmware blobs are stored
uncompressed.  Our kernel `CONFIG_FW_LOADER_COMPRESS_ZSTD=y` (added this session)
makes the **kernel** fw_loader decompress `.zst` files, which fixes ath10k Wi-Fi.

However, Qualcomm **remoteproc** loaders (modem, ADSP, SLPI) bypass the kernel
fw_loader and read firmware via tqftpserv/rmtfs — those may also need uncompressed
blobs.

**Check**: after booting with the new kernel, verify modem remoteproc starts
(`herd status rmtfs`, `dmesg | grep remoteproc`).  If it still fails, add a
`(arguments (list #:strip-binaries? #f))` pass or a post-install `unzstd` step in
`firmware-fxtec-qx1050` to decompress everything.

---

## 4. iio-sensor-proxy D-Bus activation  [LOW — auto-rotate may not work]

NixOS registers `iio-sensor-proxy` as a D-Bus activatable service so it starts
on demand when Phosh queries it.

Guix `pro1x-sensors-service-type` extends `dbus-root-service-type` but may be
missing the `.service` file that enables D-Bus auto-activation.

**Fix**: ensure `iio-sensor-proxy.service` is installed in the D-Bus system
services directory, or add it as an `etc-service-type` entry.

---

## 5. ModemManager `wants` dependency  [LOW — potential race condition]

NixOS (modem.nix): ModemManager has both `After=` and `Wants=` on rmtfs and
tqftpserv, so systemd ensures they are started first.

Guix `modem.scm` line 62: ModemManager `(requirement '(dbus-system tqftpserv rmtfs))`
— Shepherd `requirement` is equivalent to `After=` but not `Wants=`.  In Shepherd,
if rmtfs is not running, ModemManager will refuse to start rather than triggering
rmtfs automatically.  This is fine as long as `pro1x-modem-service-type` declares
all three services together, but worth verifying.

**Fix**: confirm ModemManager starts after rmtfs is up; no code change likely needed.

---

## 6. u-boot-pro1x broken build  [MEDIUM — can't rebuild U-Boot]

The current `uboot.scm` produces a broken U-Boot binary (`6z3lqjf327…`); flashing
it causes a bootloop before U-Boot is shown.  We currently rely on the cached
working build (`i2bx8zrg0z…`).

**Fix**: bisect the uboot.scm changes (configure phase, nodtb install) against the
working build.  The working build predates the `qcom-phone.config` change — try
reverting to the original merge_config approach or comparing the resulting
`.config` files.
