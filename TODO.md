# Status & remaining work

State file (AGENTS.md §5).  Rewritten 2026-10-29: the 2026-10-27/28 notes
were mostly about an image that predated about 60 commits.  Older details
are in git history (TODO.md before this commit) and in `rag-notes/`.

**On the phone (2026-10-29, evening):** generations 1 (flashed image), 25,
26 (booted) and 27 (keymap), deployed from the PC before the channel
layout change; off the network until the author pulls the channel and
reconfigures from `/etc/guix/config.scm`.  Not yet on the phone: the
U-Boot slot watcher, `modules/` layout, `/etc/guix/config.scm`, the
opt-in root key.  No release yet: tags v0.1.0-v0.1.3 were deleted
(author); the first release follows this round of fixes.

**Configuration workflow (2026-10-29):** the systems live in the channel
(`(fxtec-pro1x system mobile|minimal|mobile-encrypted)`); `systems/*.scm`
add root's key, read from `~/.ssh/pro1x-guix.pub` on the build host (made
by `scripts/flash.sh`) or `/home/user/.ssh/pro1x-guix.pub` on the phone.
The flashed system puts that public key in the user's home (skeleton) and
ships `/etc/guix/config.scm`, which inherits the system and has the
`#:root-ssh-keys` line commented out (opt-in, no key in the file).
Evaluated on the PC for the three systems: template as shipped has no
root key; uncommented gives the stock system's derivation exactly.  Not
tried on the phone.

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

## Branch `next` (2026-10-29 evening, build-tested only, not deployed)

To deploy and test once the phone takes deploys again (Tailscale):
- modem: UIM provisioning before ModemManager (SIM not detected);
- Bluetooth: BlueZ powered at start; kernel BT_LE, BT_RFCOMM;
- audio and camera: PipeWire, WirePlumber (patched libcamera),
  pipewire-pulse in the Phosh and Sway sessions; ALSA_CONFIG_UCM2;
  SailfishOS's card re-probe only if the first probe is silent here;
- sensors: iio-sensor-proxy started after QRTR 400 (nothing started it);
  open: is hexagonrpcd up before the 11 s sensor_process crash?;
- Phosh brightness: sysfs write without logind (patch);
- Sxmo: /etc/profile.d path fixed, session log; superd not packaged;
- screen off: moWerk's panel display-off patch (kernel);
- clock from the RTC with a saved offset; 16x32 console font from boot;
- kernel.scm: package lookup by name failed (current-source-directory).
The kernel changed: reboot needed, with the U-Boot fallback in mind.

Tested on the phone 2026-10-29/30 (flashed CI image of next, 2d71b95,
then deploys of next up to cc16582; generation 2 and later):
- works: SIM detected after UIM provisioning; Bluetooth controller up
  (firmware loads); brightness slider; screen off without the corrupted
  frame; 16x32 console font from boot; tuigreet order 1 Sway, 2 Phosh,
  3 Sxmo + Sway; Snapshot shows both cameras; foot starts (Sxmo's
  foot.ini used [colors]); volume keys in Phosh (gsd-media-keys).
- sound works since hexagonrpcd 40e5041: with da7a374 the ADSP crashed at
  12 s (SNS_REG_INIT, registry writes refused) and took audio with it
  (AFE -110, wcd937x -16).  It was quiet: S24_LE (the S16 rule did not
  match Guix's node names) and the speaker's HPH gain at 12 of 20; now
  S16 and 20 on the speaker.  Speaker gain 20 confirmed by ear with
  amixer; the UCM change not yet heard.
- sensors: libssc + iio-sensor-proxy 3.9 (SSC); monitor-sensor reads the
  accelerometer once polkit had the actions and a rule for users.
  Auto-rotation in Phosh not yet tested.
- SIM unlocked by the author (2026-10-30), after PUK refusals here: the
  earlier "10 left" only meant polkit stopped the requests first.
- mobile data: connected on 3G (UMTS, 28% signal); 4G allowed and
  preferred, every LTE band enabled, yet no LTE.  Another phone gets 5G
  at the same place.  Carrier profile: ROW_Commercial active, the only
  generic one among 25 (all Asian, Brazilian, Russian operators), so
  probably not the cause.  Modem usage preference is voice-centric with
  voice ps-preferred: without IMS/VoLTE a voice-centric UE leaves LTE
  if the operator lacks CSFB (inferred, not measured).  moWerk's notes:
  LTE registered on this phone (NixOS, SailfishOS) with another operator.
  Author's decision, 2026-10-30: wait; poor coverage is possible.  ASK
  THE AUTHOR AGAIN if they never see 4G while moving around: the test is
  data-centric usage, which the modem keeps in its NV (modemst via
  rmtfs); prefer a setting valid only until the modem power-cycles.
- polkit, without logind: every D-Bus service whose actions are
  allow_active only needs its package in polkit-service-type and a rule
  (ModemManager, NetworkManager: netdev; sensors: users).  polkitd does
  not see a new /etc/polkit-1 after a deploy until restarted (or reboot).
- Sway: volume keys through wpctl, capped at 120%; Sway volume keys not
  yet tested by the author.  GNOME volume above 100% via
  pro1x-gsettings-defaults, not yet tested.
- Sxmo: same device settings (/etc/sway/config.d/pro1x.conf), bus and
  audio as Sway; still needs superd.
- GPS (2026-10-30, author allowed A-GPS and data): the modem announces
  LOC (QMI 16, v2) and ModemManager lists gps-raw, gps-nmea, agps-msa/b.
  Setting the SUPL server and enabling agps-msb failed ("Failed to
  receive indication"); gps-nmea/raw enabled but "couldn't setup required
  NMEA traces: Operation timed out", and no NMEA in 30 min (indoors).
  qmicli --loc-follow-nmea for 75 s: nothing.  Two attempts, stopped;
  GPS switched off again.  No port has GPS on this phone (NixOS README:
  untested; moWerk: not started).  Next: does the LOC service need its
  engine started differently (qmicli --loc-start alone, then follow),
  or modem firmware pieces (GNSS) the stock partitions hold?  Phosh's
  location toggle needs GeoClue (not installed).  Never log coordinates.
- Phosh lock keypad flickers once on wake (low priority).
- Phosh rotation: auto-rotation works (tile: tap locks, long press
  switches auto/manual).  Each rotation flashes the screen black: phoc
  0.56 raises a black "modeset shield" on every transform change until
  the layer surfaces are rearranged, then fades it out in 150 ms
  (src/output.c).  By design; no rotation animation exists.  Smoother
  would need a phoc patch (low priority, author 2026-10-30).
  Snapshot should stay in portrait to use the whole panel; Phosh has no
  per-app rotation lock (author's wish, 2026-10-30).
- crackle at Phosh login (not at logout, author 2026-10-30).  amixer
  events during a login: PipeWire probes the Voice Call profile (Voice-
  MMode1 routes on/off, 00:12:19.2-19.9), then HiFi Speaker (HPH gain
  12->20 at 20.9).  Spk0 OUT Switch is on and never showed a change, not
  even at logout: always on, or the driver does not notify it (unknown).
  Inferred: route switches during the probe reach a live amplifier.
  Logged out (00:43): Spk0, Spk1 OUT and HPHL Switch all on, although
  the Speaker DisableSequence ran (HPH gain back to 12) and sets them
  off.  Writes take, but Spk0 was on again seconds after being switched
  off, with no session running (cause unknown).  Login at 00:44 with
  Spk1 off (Spk0 probably on): pops still heard.  amixer events needs
  about a minute to list 1279 controls before it reports changes: start
  it early.  Next: both off before login, log what turns them on and
  when, and whether pops come while both are off.  moWerk's notes: pops
  at amp power changes, NixOS too.
- a click just after login: probably the camera lens (DW9800 VCM) when
  WirePlumber's libcamera monitor opens the cameras; moWerk's
  sfos-dw9800-soft.patch (slower ramps, 2 s autosuspend, no park) makes
  it softer.  Not verified here.
- CI: U-Boot only changes with uboot.scm; reuse the last artifact when
  its derivation is unchanged instead of rebuilding.  The U-Boot step's
  failure: glib graft cannot read glib's etc/ld.so.cache (permission
  denied) under the unprivileged daemon.

Deploys (2026-10-30): scripts/deploy.sh now builds the phone's own
~/.config/guix/config.scm with its channels.scm (guix time-machine), on
the PC, plus -L modules for this tree; --repo for the old behaviour.
The phone user's config.scm and channels.scm were written from
/etc/guix's with Tailscale added (channel pinned to eac0696).  First run
in progress: builds go-std and Tailscale for aarch64 under QEMU (slow,
once).  After it: `sudo tailscale up' on the phone (author's account),
then deploy/pro1x.scm's host can be the tailnet name.

Waiting for the next deploy and a test on the phone:
- keyboard light off after 60 s without a key (backlight-timeout);
- panel dimmed to 30% after 60 s idle (pro1x-dim, Sway and Phosh);
- tuigreet remembers the last user and session (/var/cache/tuigreet);
- bluetoothctl installed: the adapter is powered (BlueZ over D-Bus);
  what fails in the UI is not known yet (ask the author);
- feedbackd (vibration), phoc rotation without black shield, Phosh
  landscape across lock/unlock with the keyboard out: deployed
  (deploy12), not yet tested.
- GPS logger running (3 h from 00:59, standalone, no coordinates).

Tailscale on the phone (author, 2026-10-30: soon), so the agent can
deploy while the phone is away from the PC (GPS tests outdoors, for
one).  The PC's tailscale package comes from umanwizard's channel
github.com/umanwizard/guix-tailscale (module (btv tailscale), 1.96.4;
built from source with go-build-system and vendored modules, BSD-3), which
the phone does not follow: either add that channel to the phone's
channels (signed: introduction 52e82318f282c555757ef077d93a685fda97565d,
key 9E53 FC33 B832 8C74 5E7B  31F7 0226 C10D 7877 B741; it also has a
tailscaled service) or package Tailscale here; author's choice.
Then tailscaled on the phone, and deploy/pro1x.scm's host switched to
the phone's tailnet name.

Updating the phone without the PC replacing its configuration: let the
phone reconfigure from its own config.scm but download what the PC built,
`guix publish` on the PC reachable over Tailscale, the PC's signing key
and URL added to the phone's guix-configuration (authorized-keys,
substitute-urls) in config.scm.  Otherwise the phone builds the kernel
and Phosh itself.  Not set up yet.

## Next big items (author, 2026-10-30)

1. **Guix Home** for the user's files: Sway config, foot, i3status-rust,
   .bashrc, phoc.ini (scale), later the author's PC scripts.  The port
   provides a default home environment the user's inherits (as config.scm
   inherits the port's system); embedded in the system with
   guix-home-service-type, so the same deploy builds both and one
   generation rolls back both.  Per-path policy in the user's home
   config, author's idea:
   - managed: read-only store link, Guix Home wins (edit the home config);
   - seeded: copied once when missing, then the user's (the user's file
     wins; later port defaults do not overwrite it);
   - unmanaged: left alone.
   Seeded is the safe default for apps that write their own config (Sxmo
   copies its defaults into ~/.config: foot.ini, sway).  dconf settings
   (GNOME Settings) are not files and stay outside.  Tonight's hand edits
   of the user's copies (sway config x3, foot.ini; .bak files beside them)
   are what this replaces.
2. **GPS**: see the GPS entry above (LOC present, no NMEA yet).
3. **Bluetooth**: adapter powered in BlueZ; find what fails in the UI
   (bluetoothctl now installed for testing).

## Next steps (author's order, 2026-10-29)

1. **Phosh settings and power key** (in progress).
   - Phosh Mobile Settings (the top-panel gear, `launch-mobile-panel`):
     `phosh-mobile-settings` 0.56 packaged in `packages/misc.scm` with a
     private `libadwaita-1.9` (uses AdwSidebar), polkit check relaxed to
     121 (only `polkit_permission_new_sync` is used), gvc,
     libcellbroadcast and gvdb pre-seeded, lm-sensors for the librem5
     plugin, binary wrapped with GST_PLUGIN_SYSTEM_PATH (it aborted on
     "playbin3 not found").  Generation 17: starts by hand and stays up;
     from the gear not confirmed yet.  Warnings: a GStreamer element still
     missing (gst_bin_add NULL), no localed permission, no cbd daemon, no
     gmobile device info for fxtec,pro1x.
   - GNOME Settings: installed; `XDG_CURRENT_DESKTOP=Phosh:GNOME` set in
     the session (ad1b59d): shows and starts (author).  Opens
     from a long press on a quick setting.  Its panels warn about missing
     hostname1 and UPower services.
   - Power key: after blanking, the screen never comes back.  phosh
     unblanks through gnome-session's presence interface, and this session
     has no gnome-session (gnome-session-shepherd does not implement
     Presence either).  Patch: unblank on power-key press when the
     presence proxy has no owner
     (`device/phosh/unblank-without-gnome-session.patch`, 7af4415): the
     power key wakes the screen and keyboard light again (author).
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
6. **Boot menu** (§3): keep a known-good entry; U-Boot command-line limit.
7. **Bootcount fallback** (§3).
8. **CI** (§5): U-Boot step, artifact size, releases.
9. **Smaller items** (§6), video decode, sway extras, user updates (§7).

---

## 1. PipeWire, WirePlumber, audio, camera

NixOS (`modules/audio.nix`, `modules/camera.nix`):
- `services.pipewire` with ALSA and Pulse, WirePlumber with the Pro¹x
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

ModemManager 1.24 sees the modem (2026-10-29).  With a SIM inserted there
is no LTE network (author, 2026-10-29): not looked into yet; check SIM
state (`mmcli -m 0`, UIM provisioning session, AGENTS.md §7), registration
and the modem's crash log.  Next, with the author:
SIM provisioning (UIM session, AGENTS.md §7), then SMS, calls, data.
Shepherd `requirement` orders but does not pull in rmtfs; check MM does
not start before rmtfs on a cold boot.

## 3. Boot menu, rollback, bootloader

- **Bootloader lookup** (fixed for generations from 26 on): on the phone,
  `guix system delete-generations`, roll-back and switch-generation look
  the bootloader up by the name a generation recorded, among those the
  phone's guix knows (not this channel).  The old name "extlinux" found
  Guix's syslinux-based bootloader (does not build for aarch64).
  `pro1x-extlinux-bootloader` is now Guix's u-boot-bootloader without its
  disk-image installer, recorded as "u-boot": `switch-generation 26` on
  the phone rewrote extlinux.conf.  After deleting generations on the
  phone, run `sudo herd start pro1x-boot-menu` to refresh the U-Boot slots
  (otherwise done at the next boot).
- **Known-good entry**: `prev1-3` cover the three newest previous
  generations only; a run of bad deploys can push every bootable one out
  (happened on 2026-10-29; recovered through U-Boot USB mass storage from
  the PC).  Keep one pinned known-good entry.
- **Command-line limit**: U-Boot's extlinux loader refuses an APPEND over
  511 bytes (CONFIG_SYS_CBSIZE=512, "bootarg overflow"); generations 22-24
  (vt.default_* palette, 569 bytes) do not boot.  Raise CONFIG_SYS_CBSIZE
  in u-boot-pro1x (needs the boot partition reflashed by the author), or
  keep the command line short.
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
  "Unrecognized image file format" (gdk-pixbuf loader?); the dark-theme
  switch changes nothing (author); battery information looks wrong
  (author; UPower is not running — GNOME Settings logs "The name
  org.freedesktop.UPower was not provided").  Not looked into yet.
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

- **Sign the channel** (low priority, author's key): `.guix-authorizations`
  with the author's OpenPGP fingerprint, a `keyring` branch with the public
  key, every commit on main signed from then on (the agent's through the
  author's gpg-agent, or signed by the author before each push), and the
  first signed commit as the channel introduction in channels.scm, README
  and `%fxtec-pro1x-channel`.  Removes the "cannot be authenticated"
  warning; guix pull then refuses unsigned commits.

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
