# Status & remaining work

State file (AGENTS.md §5).  Rewritten 2026-10-29: the 2026-10-27/28 notes
were mostly about an image that predated about 60 commits.  Older details
are in git history (TODO.md before this commit) and in `rag-notes/`.

**On the phone (2026-10-29):** generations deployed with `scripts/deploy.sh`
from the commits named below; the last one *booted* is 7 (3b1c86d), later
ones (up to 15, ad1b59d) were only activated, with the same kernel and
initrd.  `guix system list-generations` on the phone; the boot menu keeps
the newest one plus three previous (`prev1-3`).

**Reference repos** (clone to /tmp when needed):
- NixOS port (working hardware reference):
  `git clone https://github.com/nyymi609/fxtec-pro1x-nixos /tmp/fxtec-pro1x-nixos`
- Guix source + manual: `git clone https://codeberg.org/guix/guix /tmp/guix`
- moWerk's SailfishOS mainline port and sailfish-rag (AGENTS.md §4).

---

## Working (confirmed on the device, 2026-10-28/29)

- **Boot**: U-Boot + extlinux, deployed generations boot (root mounted
  with the `no-atime` flag, 3b1c86d); A/B slot success marking; rootfs
  grows on first boot.  Landscape console (`fbcon=rotate:1`).
- **Deploy**: `scripts/deploy.sh` (guix deploy) builds on the PC, copies,
  activates and rewrites the boot menu (§3).
- **USB networking**: usb0, 172.16.42.1, SSH (root by key for deploy).
- **Wi-Fi**: ath10k_snoc, NetworkManager (conf.d through
  `extra-configuration-files`, 35703cb).
- **Clock**: ntpd `-g` steps it from 1970.
- **Keyboard**: matrix driver, keyd Fn layer, layout in README; backlight
  on while slid out and the screen is on, slide-out wakes sway
  (`pro1x-kbd-backlight`, 8e5e0a7, 24738af).
- **udev**: our rules (`60-pro1x`, `90-pro1x-sensors`) and ModemManager's
  reach udev; `/dev/input/pro1x-slider`, rmnet_ipa0 tagged for MM.
- **greetd + tuigreet**: sessions Sway, Phosh, Sxmo (`LIBSEAT_BACKEND=seatd`).
- **Sway**: session, bar, launcher.
- **Phosh**: starts from tuigreet; lock screen passcode (PAM service
  `phosh`, 9c82c6a); home bar and app drawer with all apps (phoc built
  against wlroots with phoc's layer-shell patch, 8897846; app filter off);
  mutter keybinding schema for phoc (08263df).
- **ModemManager 1.24**: running, sees the modem (`mmcli -L`: Modem/0).
  Nothing beyond that tested (no SIM work without the author's go-ahead).
- **Firmware services**: rmtfs, tqftpserv, pro1x-hexagonrpcd running.
- **Channels**: `/etc/guix/channels.scm` with guix, nonguix, fxtec-pro1x.

---

## Next steps (author's order, 2026-10-29)

1. **Phosh settings and power key** (in progress).
   - Phosh Mobile Settings (the top-panel gear, `launch-mobile-panel`):
     `phosh-mobile-settings` 0.56 packaged in `packages/misc.scm` with a
     private `libadwaita-1.9` (uses AdwSidebar), polkit check relaxed to
     121 (only `polkit_permission_new_sync` is used), gvc,
     libcellbroadcast and gvdb pre-seeded, lm-sensors for the librem5
     plugin.  Not built through yet.
   - GNOME Settings: installed; `XDG_CURRENT_DESKTOP=Phosh:GNOME` set in
     the session (ad1b59d) so it shows and starts — not tested yet.  Opens
     from a long press on a quick setting.  Its panels warn about missing
     hostname1 and UPower services.
   - Power key: after blanking, the screen never comes back.  phosh
     unblanks through gnome-session's presence interface, and this session
     has no gnome-session (gnome-session-shepherd does not implement
     Presence either).  Patch: unblank on power-key press when the
     presence proxy has no owner
     (`device/phosh/unblank-without-gnome-session.patch`).  Not built yet.
2. **PipeWire + WirePlumber, then audio and camera** (§1).
   Camera shows black in cameractrl: both sensors register (imx582,
   s5k4h7), cameractrl finds the focus subdev, but no PipeWire or
   WirePlumber runs (WirePlumber not even installed), and frames reach apps
   through WirePlumber loading the patched libcamera.  Our
   `/etc/environment.d/51-pro1x-libcamera.conf` is a systemd convention
   nothing reads here.  libcamera-pro1x has no `cam` tool to test it alone.
3. **Modem** (§2): SIM provisioning, then SMS, calls and data, each only
   with the author's go-ahead.
4. **Voice-call audio**: q6voice is in the kernel; `pro1x-voice-call` /
   `voicepcm` from NixOS still to translate.
5. **Sensors** (§4).
6. **Bootloader name** (§3): `guix system delete-generations`, `roll-back`
   and `switch-generation` run on the phone fail.
7. **Bootcount fallback** (§3).
8. **CI** (§5): U-Boot step, artifact size, releases.
9. **Smaller items** (§6), video decode, sway extras, user updates (§7).

---

## 1. PipeWire, WirePlumber, audio, camera

NixOS (`modules/audio.nix`, `modules/camera.nix`):
- `services.pipewire` with ALSA and Pulse, WirePlumber with the Pro1X
  config package, `pro1x-audio-init` as WirePlumber's ExecStartPre;
- `ALSA_CONFIG_UCM2` pointing at alsa-ucm-conf merged with
  `device/audio/ucm2`;
- rtkit;
- WirePlumber's user unit gets `LD_LIBRARY_PATH=<pro1x-libcamera>/lib`, so
  PipeWire's libcamera SPA plugin uses the patched libcamera;
- a `pro1x-voicepcm` user service for calls.

Guix plan: user services through Guix Home (`home-pipewire-service-type`,
`home-dbus-service-type`) applied to `user` by `guix-home-service-type`,
or Shepherd user services started from the session scripts; rtkit;
`pro1x-audio-init` before WirePlumber; merged UCM2 tree; WirePlumber's
environment carrying the libcamera path.  Playback on speaker and headset
first, then camera in cameractrl and Snapshot.  Packages: `pipewire`,
`wireplumber` (gnu packages pulseaudio / linux), `rtkit`.

## 2. Modem

ModemManager 1.24 sees the modem (2026-10-29).  Next, with the author:
SIM provisioning (UIM session, AGENTS.md §7), then SMS, calls, data.
Shepherd `requirement` orders but does not pull in rmtfs; check MM does
not start before rmtfs on a cold boot.

## 3. Boot menu, rollback, bootloader

- **Bootloader lookup**: on the phone, `guix system delete-generations`
  (and roll-back, switch-generation) look the bootloader up by name
  ("extlinux"), get Guix's own and try to build syslinux for aarch64.
  Fix: give the channel's bootloader its own name and make it findable by
  `lookup-bootloader-by-name` (scans `gnu/bootloader/*.scm` on the load
  path).  Until then a deploy from the PC rewrites the menu.
- **Known-good entry**: `prev1-3` cover the three newest previous
  generations only; a run of bad deploys can push every bootable one out
  (happened on 2026-10-29; recovered through U-Boot USB mass storage from
  the PC).  Keep one pinned known-good entry.
- **U-Boot menu**: extlinux.conf has TIMEOUT 100, but the author sees no
  generation list on screen; the U-Boot bootmenu shows Boot and prev1-3.
- **Bootcount**: no boot-once/bootcount fallback; a kernel/initrd/USB
  change that does not reach SSH needs the author.  Fall back after N
  failed boots, cleared by `pro1x-boot-success`.
- To check: `prev*.conf` are rewritten at boot (and by `herd start
  pro1x-boot-menu`), not by a deploy; `want=n+2` in `services/boot.scm`;
  encrypted system still needs `update-encrypted-boot.sh` after a deploy.
- After a deploy that changes sessions, tuigreet shows the old session
  list until it restarts (log in and out once).

## 4. Sensors

`pro1x-sensors-service-type` extends D-Bus and udev (rules confirmed in
place).  Open: the ADSP's `sensor_process` crashed at boot on 2026-10-29
(`SNS_REG_INIT ... sns_registry_sensor.c:94`, "fatal error received");
`qrtr-lookup` is not installed (needed to wait for QRTR service 400 before
iio-sensor-proxy, as NixOS does).  Compare with sailfish-rag `Mainline/`
sensors notes.

## 5. CI

- Last run before 2026-10-29 green, but its U-Boot step failed inside
  `guix time-machine` (grafting glib-2.86.5) and the step hides failures;
  9d195b1 makes it print the failed builder's log.  The run for c372e3e
  was cancelled on purpose (author).
- Artifact: `rootfs-mobile`, 2.9 GB; `resize2fs -M` runs before upload.
  Releases only on tags (2 GiB per asset: split or zstd).

## 6. Smaller things

- Phosh: brightness goes through logind (absent; "Setting backlight on
  DSI-1 failed"); no on-screen keyboard (`sm.puri.OSK0`); background image
  "Unrecognized image file format" (gdk-pixbuf loader?).
- `cfg80211: failed to load regulatory.db` (no wireless-regdb).
- `qcom/a630_sqe.fw` fails in the initrd, loads later from the rootfs.
- `goodix_9286_cfg.bin` missing (touch uses its built-in config).
- `term-console` (agetty on ttyMSM0) exits 1 and respawns.
- Console font is the kernel's 8x16 until `setfont` runs; a larger font
  in early boot needs `CONFIG_FONT_TER16x32` + `fbcon=font:TER16x32`
  (kernel change; batch with the dpugap/panelgap sync, 69697e4 reverted in
  9f1e7c8).
- Not surveyed: battery/charging reporting, suspend, haptics/LED
  (feedbackd), GPS, Bluetooth.

## 7. Later

- **Video decode (Venus)**: needs an SM6115 video-codec DT node
  (rag-notes hardware.json "video"), then `mpv --hwdec=v4l2m2m-copy`.
- **Sway extras**: scripts from mlaparie's guix-config (nmcli-fzf, power
  menu, clamshell), i3status-rust click actions.
- **Updates for users**: substitute server fed by CI, releases pinning
  Guix and nonguix (README "Updates in the long run").
- **Upstreaming** (author's review first): libqmi 1.36, ModemManager
  1.24, phosh 0.56, phoc, feedbackd, callaudiod to Guix; firmware parts
  stay here or go to nonguix.

---

## Resolved (2026-10-28/29, details in git log and rag-notes)

- Phosh: seatd instead of `su -l`; mutter schema; libexec path; PAM
  service; home bar (wlroots patch); app filter; XDG_CURRENT_DESKTOP.
- dconf system db compiled at build time (66f1456); NM conf.d without
  shadowing /etc/NetworkManager (35703cb).
- ModemManager: D-Bus policy, udev rules (qcom-soc tag) — MM sees the modem.
- udev rules as `file->udev-rule` directories.
- NTP: `ntp-service-type` with `-g`.
- Deploy: host signing key in the deployed system (763f71a); provenance
  limited to guix, nonguix, fxtec-pro1x (dcb2dec, 850ca36).
- Root mount `no-atime` flag (3b1c86d): deployed generations 2-5 did not
  boot before it.
- tqftpserv firmware path; u-boot `text_offset`; rootfs resize.
