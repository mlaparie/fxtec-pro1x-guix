# Status & remaining work

State file (AGENTS.md §5).  Rewritten 2026-10-29: the 2026-10-27/28 notes
were mostly about an image that predated about 60 commits.  Older details
are in git history (TODO.md before this commit) and in `rag-notes/`.

**On the phone (2026-11-04):** generation 210, kernel 7.3.0, from `next`.  Lock
screen hardened: an app over it runs in a Sway mode without bindings, keyboards and
pointers off, ✕ locks before the app closes; the author's test on generation 209
"seems to work", more to come; not tried with a real call or alarm.  Cameras:
`CONFIG_V4L2_FLASH_LED_CLASS=m` brought back both sensors' media links, `cam -l`
lists back and front, and the author's verdict is that the camera app "more or less
works"; improvements later.  A backup for a reflash exists off the phone.  `main` =
`next` since this commit, merged by the author's choice before the 7.3 checks (calls,
audio, suspend, deep sleep, charging); tag `pre-7.3` (550d477) is the last `main` on
7.1, the point to go back to.

**Next:** the author's 7.3 checks (calls, audio, deep sleep, charging); then merge `next` to
`main` (author's decision, 2026-11-04), which brings detection and the `config.scm` options to
`guix pull` and reconfigure on the phone.

**Full-disk encryption: works in QEMU; prompt confirmed on the phone (2026-11-04),
never flashed.**  One system for both layouts since eed6ca6 (no `#:encrypted?`):
`flash.sh --encrypt`, also with `--rootfs`, so CI's rootfs.img works once built from that
commit or later.  From one image in QEMU (`tools/fde-qemu-test.py`, `--plain` too): plain
boots without asking; encrypted asks again after a wrong passphrase, unlocks, resizes; a
deploy updates the plain area and that generation boots.  On the phone: plain layout, #215
booted without a prompt, root mounted at 3.4 s, `/boot` not mounted, 54 services up.  Prompt
(generations 212, 213): readable in landscape, all letters and digits typed correctly
without Fn, partition found at 2.4 s, unlock with Argon2 256 MiB 4 passes: 8 s including
typing 10 digits.  Not proven until the flash: U-Boot reading the encrypted layout, the
helper's loop on UFS, the resize on 225 GB.  After the flash and before the first deploy the
plain area has no menu.env: U-Boot's built-in "Boot" entry, 3 s (read in the source; not
seen).  A reflash drops every generation, the 7.1 fallback (182) included.

**Suspend on 7.3 (2026-11-04):** smp2p-sleepstate aborted suspends, about 2 events a
second from shake-to-torch's accelerometer stream.  `pro1x-sleep` stops that service
first (generation 211).  Author: "Lock and suspend" works.

**U-Boot menu:** `bootmenu` with a countdown at each boot and generation numbers from
`/boot/extlinux/menu.env` (environment only).  Built by CI 41840039106, in boot_a since
2026-11-04 (written from the phone with `dd`; boot_b not written, old boot_a in
`~/pro1x-boot_a-2026-11-04.img.gz`).  Author's test with `menu_delay=-1`: the menu waits,
labels show generation numbers, keys work, #211 booted (`/proc/cmdline`).  Default now
15 s, deployed in #215; author: "the 15s delay worked".  In `config.scm` as
`pro1x-boot-menu-configuration`'s `delay` (15, 0 for none, -1 to wait for a key).  An older
entry does not move the system profile: `guix system list-generations` still says
"current" for the newest, `/run/booted-system` tells what runs.

**Five generations in the U-Boot menu (2026-11-04):** current plus four older, in
`make-u-boot-pro1x` and the boot menu service.  Build-evaluated only.  boot_a has the U-Boot
with three: a system with four must not reach the phone before the new U-Boot, or its
fourth label replaces U-Boot's own next menu entry.

**Incoming calls on 7.3 (2026-11-04, #215, Free on Orange's network):** on 4G the caller gets
voicemail at once and ModemManager logs no call; outgoing works, about 20 s to ringing.  On
3G (`qmicli --nas-set-system-selection-preference=umts`; `mmcli --set-allowed-modes=3g`
fails, DeviceUnsupported) it rings: ringing-in in 1 s, then "unlocked for one app" 1 s later,
but the author still saw the lock screen.  Last incoming call logged before this:
2026-11-03 17:18, boot of 09:17, probably 7.1 (author's memory; kernel not confirmed).  Not
tested: incoming on 4G with 7.1 (#182).  Restore after a test, order matters:
`lte|umts|gsm|cdma-1x|cdma-1xevdo|td-scdma` gives acquisition order lte, umts, gsm, ...

**Wi-Fi after boot:** first associated at 97-106 s and once more at 245 s (generations
212-213); SSH over Tailscale, relayed, follows minutes later.  Cause not looked into.

**On the phone (2026-11-03):** generation 203, kernel 7.3.0, from `next` (which
has 7.3 since 02218e5), over Tailscale.  `main` is behind: the phone's channel
follows it, so `guix system reconfigure` on the phone fails until `main` catches
up (its config.scm uses the new options; deploy from the PC).  Fallback: 7.1,
generation 182.  Author confirmed: rotation while locked, app menu workspaces,
sub-lists without a flash, Stevia by hand only, word completion with chosen
dictionaries, portrait menu height, quick actions, bottom swipe focus, CPU mode on
the lock screen, power menu speed, LibreWolf in portrait with the signed extension
after a restart.  Minor: switcher flicker.  Haptics: bursts from the chip's memory,
script ready and not run, on the author's go (not yet in the repository).  7.3
checklist still to do, then merge `main`: calls, audio, camera, suspend and wake,
deep sleep, charging.

**On the phone (2026-10-30, 01:20):** flashed 2026-10-29 from the CI
image of `next` (2d71b95, generation 1), then generations 2-13 deployed
from the PC (USB).  Generation 13 is the first built from the phone's own
`~/.config/guix/config.scm` and `channels.scm` (Tailscale added), with
this tree's modules in front.  `main` = `next` (d6257e1 pushed to sr.ht
and GitHub, 2026-10-30).  Root SSH by the PC's key, added by hand after
the flash and kept by deploy/pro1x.scm.  No release yet: the first
release follows this round of fixes.

**Configuration workflow (2026-10-30):** the systems live in the channel
(`(fxtec-pro1x system mobile|minimal|mobile-encrypted)`).  The phone
ships `/etc/guix/config.scm` (inherits the port's system; root SSH line
commented out) and `/etc/guix/channels.scm` (pinned guix and nonguix);
the owner copies them to `~/.config/guix/`.  `scripts/deploy.sh` builds
that copy on the PC (time-machine with the phone's channels, `-L
modules`); `--repo` deploys `systems/*.scm` instead.

**Reference repos** (clone to /tmp when needed):
- NixOS port (working hardware reference):
  `git clone https://github.com/nyymi609/fxtec-pro1x-nixos /tmp/fxtec-pro1x-nixos`
- Guix source + manual: `git clone https://codeberg.org/guix/guix /tmp/guix`
- moWerk's SailfishOS mainline port and sailfish-rag (AGENTS.md §4).

---

## State, 2026-11-02 night

- Phone: generation 142 (userspace of c1324fa minus the last pro1x-osk
  fix; kernel 3nfp9v97, modem wake v3).  CI run 41368293086 (main,
  550d477) builds the kernel with dw9800-soft and modem wake v4: import
  it, deploy, reboot, then suspend with the SIM registered.
- Confirmed by the author tonight: calls wake the phone from suspend
  (v3); the camera flash works (0.6 s pre-flash).
- Open: suspend held only while unregistered (v4 is the fix); camera
  colours (no CCM), slow exposure; one landscape photo to check the
  accelerometer turn; stevia slowness and text fields (it was running:
  the earlier "not running" was a wrong check).
- If the phone reboots before the next deploy, pro1x-osk run spins
  (fixed in c1324fa): kill it by PID.
- Later the same night (generation 150): stevia without its slide
  animation shows "much faster" (author); the earlier tests ran the old
  stevia, not restarted after its deploy: restart stevia after a stevia
  deploy.  Haptics on menu swipes and the power hold work once fbcli is
  fed from a sleep (felt by the author); menu swipes act at 80 px with the
  finger down.  sov works with its own style only.  Charge limit
  overshot to 91% once (gauge jump suspected, not measured): battery
  trace running again (/root/charge-trace.sh, until reboot).

## State, 2026-11-03 night

- Phone: generation 179 (next e476eb7: everything of 2026-11-02/03, see
  DEBRIEF-2026-11-03.md), kernel wiqj3i9r (7.1, modem wake v4,
  dw9800-soft), time zone Europe/Paris.
- 7.3 trial: branch kernel-7.3-trial, kernel n9iv2m73 (CI 41551104730)
  in /tmp/cik73t, path checked; full image run 41564798402.  Not booted.
- Loggers still running on the phone until reboot: /var/log/pro1x-flash.log,
  /var/log/pro1x-pm-latency.log.

## State, 2026-11-02 morning

- Phone: generation 153 (next 2d2ac45: libcamera 0018, Night button),
  kernel still 3nfp9v97 (7.1, modem wake v3).
- To import (author's sudo): 7.1 kernel wiqj3i9r (CI 41378484852, modem
  wake v4 + dw9800-soft) in /tmp/cik; 7.3 kernel i5n6m4fc (CI 41388196979,
  branch kernel-7.3 with next merged) in /tmp/cik73.  Neither booted.
- Debrief for the author: DEBRIEF-2026-11-02.md (untracked).

## Camera exposure: libcamera never lengthens the frame (plan, 2026-11-02)

Measured on the phone (rag-notes hardware/camera): the IMX582's 1080p mode
runs at its minimum blanking (70 lines), so no exposure can exceed 10.4 ms,
asked or automatic; the dark indoor photos follow from it.  The sensor
driver allows blanking up to 64420 lines (~0.6 s exposures).  libcamera's
simple pipeline takes the exposure limit at configure time and never writes
VBLANK.  Plan:
Step 1 done (2026-11-02, device/libcamera/af/0018): exposures up to 619 ms
applied on the phone, auto up to 66 ms.  Steps 2-3 open.
1. A libcamera patch (soft IPA): exposureMax from the VBLANK maximum; per
   frame, VBLANK = max(minimum, exposure + margin - height), sent with the
   exposure through DelayedControls (VBLANK registered with the exposure's
   delay); FrameDurationLimits honoured.  Model: src/ipa/rpi/common and
   rkisp1's agc handling of vblank.  Build in CI (C++ under emulation is
   slow), test with the headless test (camtest.py in the agent's notes:
   asked exposure vs applied, mean brightness).
2. The camera app: a Night/long exposure button (manual exposure up to
   ~0.5 s, gain moderate) once 1 works; the viewfinder keeps 30 fps.
3. Check whether moWerk's camerabin work hit the same cap (his notes).

## Kernel 7.3 upgrade (planned, branch `kernel-7.3`; author, 2026-11-02)

Why: deep sleep.  On 7.1 the SoC never reaches vlow/vmin (qcom_stats 0,
rag-notes hardware).  moWerk's SailfishOS port runs 7.3 with 57 patches
(github.com/moWerk/sailfishos-pro1x-mainline, `kernel/patches-7.3/`),
several aimed at exactly that, with sleep currents measured on the
device (73-79 mA, then 49 mA with 0053; reported, not verified here).

Where we are: 7.1.0 from the sm6115-mainline tree, the NixOS port's
patches (`device/kernel/patches/`) plus ours (fastrpc wake/resume,
q6v5 handover, qrtr modem wake v4, imx582 1080p, dw9800 soft).  Their
0001-0011 are the same NixOS series rebased; 0014/0015 we already
carry; 0033/0034 are the fastrpc patches we took from haltia.

Plan:
1. Branch `kernel-7.3` off `next`; the kernel only, userspace unchanged.
2. Base: the sm6115-mainline 7.3 tree moWerk builds on (find the commit
   in his kernel/HANDOVER.md); a `linux-pro1x-7.3` package next to
   `linux-pro1x`, so `next` keeps building 7.1.
3. Series: moWerk's 0001-0011 instead of ours (same origin), then ours
   rebased (qrtr modem wake, q6v5 handover; drop what 7.3 or his series
   already has), then his fixes by group, one CI build each:
   a. hardware fixes: 0016-0031 (charger, amplifier, GPU bandwidth,
      panel, UFS QoS, flash LED link, keyboard backlight, qrtr HELLO,
      ath10k);
   b. sleep: 0032 (SMP2P sleep state), 0035-0041, 0044-0057 (MPM,
      cluster idle states, USB GDSC retention, panel enable, LPASS vote,
      UFS power-down, dispcc), in his order, skipping his reverts (0043).
   Each patch keeps its origin and licence in its header (AGENTS.md §6).
4. Config: diff his sfos.fragment against `device/kernel/config.aarch64`;
   take only what a patch needs (V4L2_FLASH_LED_CLASS for 0027 only if
   the camera app moves to the V4L2 flash).
5. Test on the phone, one generation per group, the 7.1 generation kept
   as fallback in the boot menu: boot, modem and calls, audio (speaker,
   earpiece, call audio), camera, Wi-Fi/Bluetooth, then suspend:
   qcom_stats vlow/vmin counts and the drain over a night (QG FIFO, as
   moWerk measures).
6. Merge into `next` when suspend reaches vmin and nothing above
   regressed.

Open questions: whether nonguix's linux-firmware matches what 7.3's
drivers ask for; whether his DT changes (sfos-dt, 0012) are
SailfishOS-specific.



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

## Branch `next`, 2026-10-29 evening (now on `main` and the phone)

What the evening round contained (results below):
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
  Later the same night: GNOME Settings' "4G only" fails ("the given
  combination of allowed and preferred modes is not supported"):
  ModemManager's supported list has no 4G-only entry (2G, 3G, 2G+3G,
  2G+4G, 3G+4G, 2G+3G+4G).  Cell info (qmicli
  --nas-get-cell-location-info, read-only): one UMTS serving cell, one
  UMTS neighbour, the "Neighboring LTE" section empty while another phone
  gets LTE/5G there.  So the modem does not measure or report LTE cells:
  points at the modem's configuration (voice-centric, carrier profile)
  rather than coverage (inferred).
  Network scan (qmicli --nas-network-scan; stores nothing): LTE networks
  are heard (radio type lte, beside umts); data stayed on UMTS.  So RF and
  bands work and the modem chooses not to use LTE: configuration
  (voice-centric without IMS, or carrier profile), still inferred.  The
  data-centric test needs a libqmi program (qmicli 1.34 cannot set the
  usage preference); its change-duration "power cycle" may or may not be
  honoured by this firmware, so it may persist in NV: not done, author
  wants no risk (2026-10-30).
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
  (src/output.c).  By design; no rotation animation exists.  Patched to
  skip the shield for rotation alone (0491931): "much better" (author,
  2026-10-30), but still not instantaneous, with visible artifacts while
  apps redraw.  Next: measure where the time goes (sensor-proxy event to
  transform commit, client re-layout).  Snapshot must stay portrait
  whatever the rotation mode (author: "should really never rotate").
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

Tailscale deploys work (2026-10-30): bash scripts/deploy.sh <tailnet
address> deployed generation 22 over the tailnet; the host key was checked
against the USB one first (same SHA256).  The address itself stays out of
git (tailscale ip -4 on the phone).

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

## Waiting for the author (2026-10-30, 04:30)

- Login pops: fixed (2624e73, generation 30): the author no longer hears
  them (2026-10-30).  The agent's login on generation 31 logged the
  session script setting the amp switches off and WirePlumber setting
  them on 3 s later, with 0 amp power-ons during the probe.
- On-screen keyboard (stevia), Esc wakes the panel, MMS reminders and the
  Fetch MMS launcher: deploying (deploy30); need a relog and a try.
- CI kernel (charge limit, LED pattern trigger): run 41025825198 green
  (warm-up step da730ed passed); kernel q1i51w54 imported on the PC,
  generation 30 (2624e73 + 4de272d), booted 2026-10-30 ~10:07.  Comes
  back to tuigreet; modem probes (Modem/0, SIM present, PIN-locked as
  after every boot: the author enters the PIN).  Charge limit and LED
  trigger not tested yet.  Merge next into main: author's call.
- "Forgot the Wi-Fi passwords" after the reboot into 30 (author): not a
  loss, from NetworkManager's log (confirmed in the log; the networks'
  names compared only as hashes).  Before the reboot the phone had left
  its saved Wi-Fi at 09:03 and was on mobile data; after the reboot the
  SIM was PIN-locked (no data, so offline), and the Wi-Fi in reach had
  never been saved (its SSID and PSK match neither saved profile).  The
  three Wi-Fi profiles are all in /var/lib/NetworkManager with their PSK.
  One of the older ones has autoconnect=false.  10:57-11:05 the new one
  dropped 8 times: deauth reason 1, then ssid-not-found (the AP went
  away: the phone is on a 4G phone hotspot (author), which fits);
  stable since.  Possible
  improvement: a reminder for the SIM PIN at login, since mobile data
  (and Tailscale) depend on it.
- ADSP log spam: "qcom_q6v5_pas a400000.remoteproc: Handover signaled,
  but it already happened", 4.4 a second (confirmed 2026-10-30).  Cause:
  the accelerometer stream that sway-autorotate's monitor-sensor keeps
  open through iio-sensor-proxy and libssc.  The ADSP raises its SMP2P
  "ready" and "handover" bits again with each sensor batch (equal
  counts, 15502/15501; wdog and fatal 0); the driver logs every rising
  handover edge after the first (q6v5_handover_interrupt).  Measured:
  smp2p-adsp interrupts 43/10 s with monitor-sensor, 0 without, 44 after
  restarting it.  It started at the first login (10:19), not at boot.
  (An earlier note here said "not monitor-sensor": that test killed
  nothing, the process is named .monitor-sensor.)  About 390000 log lines
  a day, and the ADSP woken 4 times a second while rotation is on.
  Kernel patch ceb256b logs the repeats at debug level: CI run
  41048883373, then import, deploy, reboot.  Stopping the stream with
  the screen off: not wanted for now (author: the accelerometer may be
  useful with the screen off).  Phosh releases the accelerometer when
  the screen blanks, rotation is locked or auto-rotation is off
  (rotation-manager.c claim_or_release_accelerometer);
  sway-autorotate keeps it while toggled off.
- Not deployed yet (wait for CI run 41048883373's kernel, which
  ceb256b needs): 63db506/e1da441 no console=ttyMSM0; 0c05b2d
  sway-autorotate holds the accelerometer only while on and lit, like
  Phosh (tested by hand in the session); 26bd986 notification-leds in
  pro1x-hardware-configuration (feedbackd device theme; colours tested
  through a user theme); 0b75620 Sway caffeine quick setting and
  rotation state in ~/.local/state (tested by hand in the session);
  caffeine back in $XDG_RUNTIME_DIR, not kept across reboots (author).
  After deploying and rebooting: check that the rotation state survives
  the reboot and caffeine does not, the device theme loads (set a
  colour in config.scm), term-console stops respawning, no handover
  lines.
- RGB LED colours (2026-10-30): sysfs red, green, blue, white, #800080,
  #00FFFF written in turn (multi_intensity, brightness 255); what the
  author saw: asked.  feedbackd's defaults light it (SMS blue, missed
  call cyan).
- Toggle persistence: Wi-Fi and mobile radios (NetworkManager.state),
  feedback profile (GSettings), volume and mute (WirePlumber) persist
  already (from their storage; reboot not checked).  Auto-rotation kept
  "off" across the reboot into 34, caffeine was gone (confirmed).
  Bluetooth: NOT persisted.  33915ed restored an rfkill block at boot;
  in generation 34, with Bluetooth blocked from boot, `rfkill unblock
  bluetooth' never returned and the phone hung (black screen, red LED,
  no keys; hard reboot, 2026-10-30 ~13:37).  /var/log/messages stops at
  13:35:08, so the cause is inferred from the timing only.  Block and
  unblock of a Bluetooth powered at boot did work (twice).  Reverted
  (c9f6b8f, generation 35); /var/lib/pro1x/rfkill-bluetooth set to 0.
  Do not unblock Bluetooth in a boot that started with it blocked.  To
  find out: a logger that survives the hang (dmesg -w over SSH to the
  PC) and the author's go-ahead.  Torch and caffeine: not persisted on
  purpose.
- 2026-10-30 evening round (generations 41-43), author's list:
  quick actions (notifications and Lock first, signal % first, cycling,
  Super+q closes, dock OK/Tab dismiss), portrait with the keyboard closed
  (Sway and Phosh), Chatty and Calls in the background (Sway only),
  stevia patched for Sway (phoc's device-state protocol optional; not yet
  seen drawn), notification wake and lock refresh (pro1x-notify),
  "Guix" in yellow on the lock screen, battery LED patterns (yellow
  breathing charging, green full/held, red blip low; seen by hand),
  freedesktop sound theme, edge swipes (pro1x-gestures: all three work in
  landscape, author), Calls fullscreen/portrait rule.  Vibration works
  (fbcli phone-incoming-call, author).  Ringtone: profile was quiet.
  Need a Sway relog to test most of it; an incoming call for Calls.
- Generations 44-45 (2026-10-30 evening): foot server with footclient
  for quick actions, launcher, switcher and Super+Return (pro1x-term;
  Super+Shift+Return plain foot); pro1x-call-watch (incoming call while
  locked: unlock with swaylock SIGUSR1, relock when the call is deleted;
  the phone stays unlocked during the call); notification wake at half
  the dim level with the backlight at 0 across power-on (red flash,
  author); Calls fullscreen/portrait rule.  The author's Sway config has
  all of it (backups beside it).  Needs a Sway relog; calls need a call.
- Swipes (pro1x-gestures): the switcher toggles (second swipe closes,
  log), the launcher did not: at the second swipe no launcher window was
  open, in released and pressed modes.  Guess, not checked: the lift
  that ends the swipe taps inside the new launcher and starts an entry.
  Asked the author what they saw (they answer later).  The session runs
  the logging copy /tmp/gestures-dbg (pressed mode) until the next login.
- Proximity works (2026-10-30 21:44): iio-sensor-proxy (monitor-sensor
  --proximity: 0/1) and ssccli (NEAR/FAR) followed every cover/uncover
  by the author.  Two earlier tests saw no change: wrong timing against
  the logger, or the first reading only (the corrected note said "not
  working": wrong).  Next: blank the panel near the face during calls in
  Sway (pro1x-call-watch); Phosh does its own.
- Blank after 180 s, dim at 150 s (3ee97f9, 59ad954): Phosh's own
  [org.gnome.desktop.session:Phosh] idle-delay=60 had kept Phosh at 60 s;
  generation 40's Phosh session: swayidle dims at 150, blanks at 180
  (confirmed).  Sway lock screen (f083a22, pro1x-lock): rendered on the
  PC only; check at the next Sway lock.
- Generation 34 (2026-10-30 13:33): CI kernel 3zg5vbvf (handover patch),
  no console=ttyMSM0: 0 handover lines, term-console idle ("no serial
  port console requested"), no respawns (confirmed).
- OSK: stevia runs in Sway (started by hand; Visible follows SetVisible).
  22e3cff starts it from the Sway config, Super+k and a Keyboard line in
  quick actions show/hide it (the Sway config is a skeleton: existing
  accounts need the lines).  Drawn and typing in Sway: not yet seen.
  Phosh: works in generation 40 (author, 2026-10-30): stevia on text
  fields with the keyboard closed, hidden with it out.  Causes found:
  GTK 3 had no IM modules (d6641f0), stevia disabled itself for the
  always-attached keyboard (ignore-hw-keyboards), and the override did
  not reach stevia until it went into stevia's own compiled schemas
  (f083a22, 223a2fa).  Sway: 9d04238 pro1x-osk-slider (added to the
  author's ~/.config/sway/config with stevia and Super+k, backups
  beside it).  At the next Sway login, check: stevia on a text field
  slid in, none slid out, Super+k, the Keyboard line, the bar gear.
- Quick actions (33a09c7, 7f8d774): battery header, Wi-Fi network and
  signal, mobile technology/signal/operator, charge limit line (from
  /etc/pro1x/charge.conf), Right on / Left off for every toggle, bar gear
  (skeleton i3status-rust config; the author's copy needs the block).
  Modem on LTE now (signal 52-60%, 2026-10-30, after the PIN).
- sway-autorotate (0c05b2d, run by hand): ended with the Sway session at
  the logout (confirmed).
- Sway quick actions (Super+q), generation 33 (9c452f5): SIM line with
  PIN entry (e87e971), one fzf with reload (0.47 s per reload on the
  phone), Left/Right on Brightness/Volume, Mute shows muted or the
  volume, notification dock (mako over D-Bus: preview, Enter default
  action, Tab pick, Del dismiss, ^X all).  Tested on the PC with stubs
  and the helpers as the user on the phone; works on the phone (author,
  2026-10-30).
- Sway landscapes upside down (author): 8430c1f swaps left-up/right-up
  (generation 31); works (author, 2026-10-30).  4de272d's watcher did not stop
  monitor-sensor (.monitor-sensor, wrapped); fixed in the next commit.
- guix pull as user on the phone: running (window 3).
- Calls speaker/mute: a measurement call when the author has time.

- term-console restarts every 10 s (4566 times in /var/log/messages):
  Guix's serial getty runs on the console= of the kernel command line,
  ttyMSM0, and /dev/ttyMSM0 does not exist (no UART enabled), so agetty
  exits with 1.  63db506 drops console=ttyMSM0 (mobile, minimal,
  mobile-encrypted; flash-encrypted.sh and update-encrypted-boot.sh
  keep theirs); deploy with the CI kernel, then reboot.

## Research notes (2026-10-30, agent)

- **GPS**: ModemManager (QMI) lists gps-raw, gps-nmea, agps-msa/msb and
  has gps-raw and gps-nmea enabled, but `mmcli --location-get` returns no
  NMEA at all, not even fixless sentences (confirmed, indoors).  moWerk's
  direct QMI LOC client (LOC service 16 over QRTR, REG_EVENTS + START)
  gets NMEA at 1 Hz indoors without a fix (reported,
  sailfishos-pro1x-mainline notes/gnss.md).
  ModemManager's debug log (confirmed): it sends LOC Register Events and
  Start, reads the NMEA types and gets "none", and no NMEA or position
  indication ever arrives.  moWerk got NMEA after setting the types.
  Next (asks the author: it changes a modem setting that may persist;
  revert is setting "none" again):
  `qmicli -d qrtr://0 --loc-set-nmea-types="gga|gsa|gsv|rmc|vtg"`, then
  re-enable gps-nmea in ModemManager; then geoclue (modem source) and
  XTRA/time injection for faster fixes.
- **Fingerprint**: side sensor; nothing in the mainline device tree, the
  NixOS port or moWerk's notes, and no mainline or libfprint support found.
  Qualcomm phones usually route such sensors through TrustZone (inferred,
  not checked for this phone).  Needs the stock device tree or vendor
  sources to identify the part and its bus; not worth more without them.

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
3. **Bluetooth**: works from Phosh once gsd-rfkill runs and /dev/rfkill
   is writable by netdev (acc408c; author, 2026-10-30).  Pairing with
   a speaker works, and sound plays on it (author, 2026-10-30).
4. **Sway quick actions** (low priority, author 2026-10-30): an fzf menu
   like sway-window-switcher for Wi-Fi (the author's nmcli-fzf), mobile
   data, Bluetooth, torch, auto-rotate, brightness, volume, later
   location.  Auto-rotate needs a Sway rotation helper: rot8 1.0 (in
   Guix, author's suggestion) reads only raw IIO sysfs, which the SSC
   accelerometer is not, so sway-autorotate following monitor-sensor
   --accel, with an on/off toggle, a force (sway-rotate, which turns
   auto off) and landscape while the keyboard is out.
5. **On-screen keyboard**: none in Guix at the pin; package stevia (C,
   GTK 4) rather than squeekboard (Rust).
7. **Notification LED**: rgb:status (multicolour) exists in sysfs.
   feedbackd 0.8.1 drives LEDs for events (fbd-ledctrl) when a udev rule
   tags them; check it handles multicolour LEDs.  moWerk drives the same
   LED with mce (53d590a).  Author, 2026-10-30.
10. **Calls: speaker and mute buttons** (2026-10-30, two attempts,
   stopped).  Calls work (received a call, both directions).  Buttons
   reach callaudiod; callaudiod 0.1.9 switches sink ports, which PipeWire
   1.2+ does not have here (one profile per output; ConflictingDevice in
   UCM changes nothing; callaudiod upstream deprecated, speaker switching
   in calls open upstream, pipewire issue 4868).  Now pro1x-voice-call
   follows callaudiod: test call 03:10 logged the profile switching to
   Voice Call (Mic, Speaker) and back, and the VoiceMMode1 capture route
   off/on with mute, keep-alives running; but no audible change (author:
   no speaker, caller still heard while muted).  Next: measurement, not a
   fix: amixer snapshots during a call before/after each button, to find
   which routes the DSP voice session really uses.
9. **MMS** (receiving works, 2026-10-30, author): the operator uses one
   combined APN for data and MMS; the separate MMS APN entered at first
   (and later a mistyped proxy port) was the whole problem.  After
   correcting the settings in Chatty, mmsd-tng (restarted to reprocess
   its queue) fetched the four waiting MMS at once.  Sending works (author,
   2026-10-30, Chatty).
   History below.
   mmsd-tng 2.6.4 packaged and started with Phosh (ff2261c).
   It receives the MMS notifications (WAP push: transaction id, location)
   but does not download: the active mobile-data connection's APN differs
   from the MMS APN, and mmsd-tng only downloads over the active bearer
   when its APN equals MMS_APN (it opens no second bearer).  Its README
   says so: "can only support one bearer at a time ... will not function
   with carriers that have two APNs".  The author's operator has two;
   MMS APN = data APN in Chatty did not help (the MMSC is only reached on
   the MMS APN).  Options: (1) mobile data on the MMS APN, if the operator
   routes data there; (2) a helper switching the NM connection to the MMS
   APN while mmsd downloads, then back; (3) a second bearer in mmsd-tng
   (upstream-sized).  Operator, APN and MMSC values stay out of git.
   Option 3 (2026-10-30): the first two tests used a mistyped MMS APN
   (author), so their "ServiceOptionNotSubscribed" proved nothing
   (corrected).  With the right APN: the second link is created
   (qmapmux0.1, mux id 2); without its own profile IPv4 failed with
   "call-already-present" (same profile slot as data) and IPv6 with
   option-unsubscribed; with its own 3GPP profile (MMS APN, IPv4, type
   mms, author's OK) the network refuses: 3GPP cause 33, option
   unsubscribed.  So this subscription allows no MMS context beside data,
   on 3G at least: option 3 closed.  The profile was deleted and the
   profile list compared with a snapshot: identical; data stayed up.
   Option 2 (helper, with confirmation) it is; its notify-send returns at
   once without an answer when the helper runs it (by hand it waits):
   not solved yet.
8. **Fingerprint reader**: research first: which sensor, whether it is
   reachable on SPI or only through TrustZone (likely, on Qualcomm),
   any mainline port or libfprint driver.  Author, 2026-10-30.
6. **Camera**: moWerk's libcamera 0.7.2 patches are in (identical to his,
   2026-11-01), and his IMX582 1080p widening is in the kernel.  Snapshot
   stays limited (PipeWire's 1080p stream, no focus, ISO or stills).
   Chosen (author, 2026-11-01): a qtmultimedia@5 variant with moWerk's 13
   camerabin patches (libcamerasrc, tap-to-focus, ISO, exposure
   compensation, flash LED; sailfishos-pro1x-mainline patches/qtmultimedia)
   and a small Qt Quick camera app of our own on it (viewfinder, tap to
   focus, ISO, flash, full-resolution stills; portrait and landscape),
   reusing BSD camera logic from sailfishos/jolla-camera where useful
   (its Silica UI cannot be used).  Kernel flash-LED link (moWerk 0027)
   in a later kernel batch.

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

## 1. Audio and camera

Done 2026-10-29/30 (see "Tested on the phone" above): PipeWire,
WirePlumber, pipewire-pulse per session from the session scripts (not
Guix Home), patched libcamera in WirePlumber, speaker plays, both
cameras in Snapshot.  Open: pops at login, earpiece, headphones,
microphones, call audio (pro1x-voicepcm), rtkit (PipeWire warns it is
missing; no audible effect noticed).

## 2. Modem

SIM detected (UIM provisioning every boot), unlocked, data on 3G
(2026-10-30).  Open: LTE (see "mobile data" above: ask the author again
if no 4G while moving around), SMS, calls (ask before each, AGENTS.md
§0).  Shepherd `requirement` orders but does not pull in rmtfs; check MM
does not start before rmtfs on a cold boot.

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
- After a deploy that changes sessions, tuigreet shows the old session
  list until it restarts (log in and out once).
- Since 2026-10-30 deploys build the phone's own config.scm; check
  that a deploy after the owner edits config.scm keeps the edit.

## 4. Sensors

Accelerometer and auto-rotation work (2026-10-30): hexagonrpcd 40e5041
stopped the ADSP's SNS_REG_INIT crash, iio-sensor-proxy 3.9 with libssc
reads the sensors, polkit lets users claim them.  qrtr-lookup is
installed and iio-sensor-proxy waits for QRTR 400.  Open: proximity
(screen off in calls), light, gyroscope; check the accelerometer axes in
all four orientations (mount matrix from the NixOS port).

## 5. CI

- Last run before 2026-10-29 green, but its U-Boot step failed inside
  `guix time-machine` (grafting glib-2.86.5) and the step hides failures;
  9d195b1 makes it print the failed builder's log.  The run for c372e3e
  was cancelled on purpose (author).
- glib graft (2026-10-30, confirmed in the logs): it fails on the first
  `guix time-machine` call of a run and the next call builds the same
  profile.drv (hxsm7g0s…) without it failing (run 40946059940: U-Boot
  failed, Prefetch then passed).  95c1257 moved U-Boot after the image,
  so Prefetch became the first call and failed the job (40997348185,
  41007214587).  The cause of the first failure is not known (a race
  with the substituted glib under the unprivileged daemon is a guess).
  Workaround: a "Build the pinned Guix" step that retries once.  If the
  retry also fails, that is the second failed fix (AGENTS.md §4.5): stop.
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
