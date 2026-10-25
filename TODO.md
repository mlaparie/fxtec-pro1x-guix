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

## 3. Firmware path for tqftpserv  [FIXED — symlink created at service start]

NixOS patches tqftpserv to use `/run/current-system/firmware/` and NixOS creates
that symlink during activation.

Guix's `activate-firmware` only writes to `/sys/module/firmware_class/parameters/path`
— no symlink.  `misc.scm` patches tqftpserv to `/run/current-system/firmware/` but
that path doesn't exist.

**Fixed**: `modem.scm` tqftpserv start now creates the symlink at service-start
time by reading `firmware_class.path` from sysfs — no hardcoded store paths.

Modem remoteproc was verified starting OK in the old system (`.zst` decompression
wasn't needed by remoteproc — it loads via the kernel's own fw_loader).
ath10k Wi-Fi still needs the new kernel with `CONFIG_FW_LOADER_COMPRESS_ZSTD=y`
to decompress `board-2.bin.zst`.

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

---

## 7. GitHub CI  [FIXED — but verify green run]

CI was failing at the "Build u-boot-pro1x" step because `.github/workflows/build.yml`
copied `u-boot.bin` from the store but `uboot.scm` installs `u-boot-nodtb.bin`.

**Fixed in this session**: changed all three occurrences in `build.yml`
(`cp`, upload artifact, release) from `u-boot.bin` → `u-boot-nodtb.bin`.

**Verify**: the in-progress CI run triggered by the latest push should now pass
the U-Boot step.  If the system image step then fails, the next likely cause is
disk space (runner arrives ~70% full; ~25 GB needed for kernel + image build)
or a missing `--system=aarch64-linux` flag (runner is already aarch64 so likely
fine).
