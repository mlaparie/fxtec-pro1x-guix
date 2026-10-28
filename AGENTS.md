# AGENTS.md: an LLM coding agent porting Guix System onto the Pro1X with a mainline kernel

This file instructs a coding agent (Claude Code, or any agent that reads AGENTS.md) working
on this repository: GNU Guix System on the F(x)tec Pro1X (Qualcomm SM6115), with **no vendor
kernel, no libhybris, no halium**: a near-upstream Linux kernel, the device's firmware blobs,
and a Guix userspace with Shepherd, not systemd.

It is adapted from the AGENTS.md of moWerk's SailfishOS port of the same device
(github.com/moWerk/sailfishos-pro1x-mainline). That file was distilled from a working session
that brought most of the hardware up on a 7.3 kernel. The hardware lessons are kept here.
The OS-specific parts were rewritten for Guix, using this repository's own history.

The hardware reference for this port is the NixOS port, nyymi609/fxtec-pro1x-nixos, which
works almost completely. Its `device/` tree is meant to be distribution-neutral. Its `modules/`
assume NixOS and systemd and have to be translated, not copied.

---

## 0. Local setup

| what | value |
|---|---|
| Author (the person who owns the work) | mlaparie |
| Device, SoC | F(x)tec Pro1X (QX1050), SM6115 / Snapdragon 662 |
| Kernel | `linux-pro1x` in `fxtec-pro1x/packages/kernel.scm`; patches and config in `device/kernel/` (from the NixOS port) |
| Target OS | Guix System; channel commits pinned in `channels-lock.scm` (local) and `channels-ci.scm` (CI) |
| Repositories | sr.ht `~mlaparie/fxtec-pro1x-guix` (primary, `origin`), GitHub `mlaparie/fxtec-pro1x-guix` (mirror, CI) |
| How the agent reaches the device | `ssh user@172.16.42.1` over USB gadget Ethernet, then `sudo` |
| Fallback on the device | previous Guix system generations, in the U-Boot extlinux menu (hold volume-down at power-on; needs the author's hands) |
| Build host | x86_64 with QEMU binfmt for aarch64 (`--system=aarch64-linux`); GitHub Actions builds natively on aarch64 |
| Where findings are written | `rag-notes/` in this repository (format in `rag-notes/README.md`) |
| Hardware reference | NixOS port, cloned to `/tmp/fxtec-pro1x-nixos` when needed |
| Standing permissions | see below |

Standing permissions, set by the author:

- **Device**: the Pro1X only. Never any other phone, in particular the author's daily one.
- **On the Pro1X, without asking**: `sudo`; deploying generations and rebooting into them,
  including kernel, initrd, boot-service and USB-network changes (tell the author before such
  a reboot, since a failure needs their hands at the boot menu); `herd` start/stop; loading and
  unloading modules; mixer changes; joining Wi-Fi networks and changing NetworkManager
  settings. Not the modem remoteproc (§2).
- **Ask each time**: placing calls, sending SMS, using mobile data on the author's SIM.
- **Build host**: long `guix build` jobs freely; `guix shell <pkg> -- <cmd>` freely for tools
  not installed on the host (e.g. `guix shell github-cli -- gh` for CI runs and logs);
  `guix gc` only after asking. Run commands in the author's command pane in tmux session
  `1` (the right-hand pane of window 0, next to the agent; target it by pane id, e.g.
  `tmux send-keys -t %5`), so the author can watch them, rather than in background
  processes the author cannot see.
- **Git**: commit freely on this channel; push (to sr.ht and GitHub) when the author asks.
  Triggering or re-running GitHub Actions jobs is fine.
- **Upstream** (Guix, nonguix, the NixOS port, the kernel): never without the author's review
  of the final series.
- **Quiet hours**: none set; when the author is away, follow §1 (log, no sound, no wake-ups).

The device password goes in the agent's private local config, never in this file and never in
git. The `123456` in the README is the documented first-boot default, not the live password.
The agent uses the password itself (sudo over ssh) instead of handing commands back.

---

## 1. Who does what

- The **author** owns the port: goals, decisions, anything public, every reply to other
  people. The agent is a tool that does the work and writes it down. Say "author" or the
  person's handle, never "the human".
- The agent works **autonomously on dev devices** the author named. It runs commands,
  builds, deploys generations, reads logs, without relaying commands back for the author to
  type. If it needs the author's hands (a call, covering a sensor, plugging USB, picking an
  entry in the boot menu), it asks once, precisely, and says what it will record meanwhile.
- **Never touch a device the author did not name**, especially a daily phone.
- While the author holds the device, no blocking waits and no timed bursts: arm a logger,
  ask the author to act, read the log afterwards. Screenshots or measurements on the author's
  cue ("now"), one per cue.
- Overnight or unattended: no sound, no display wake-ups; log instead.

## 2. Never do (hard rules, no exceptions)

- **Never write, erase or "restore" `persist`, `modemst1/2`, `fsg`, `fsc`** or any partition
  holding calibration, IMEI or modem state. They are per-unit and irreplaceable.
  `scripts/backup-stock.sh` prints restore commands for them: the agent never runs those.
  Restoring is the author's own decision, done by the author by hand.
- **The agent never runs `fastboot flash`, `fastboot erase` or `fastboot set_active`.** First
  installs are done by the author with `scripts/flash.sh` or `scripts/flash-encrypted.sh`.
  When the agent changes a flash script, it reads the whole script back for the partition
  names above, and says which partitions and slots the script writes.
- **Never stop the modem remoteproc** (`echo stop > /sys/class/remoteproc/*/state`) to "reset"
  it. On the Pro1X (in moWerk's SailfishOS port, same SoC) it crashed the kernel. Reboot instead.
- Disabling DSP recovery (`recovery=disabled`) means a DSP crash leaves it down until reboot
  (audio gone with an ADSP crash). Know which DSP your experiment can crash before you start.
- **Never delete system generations on the device** (`guix system delete-generations`, or a
  `guix gc` after deleting them). They are the only rollback this port has.
- Never commit or publish: passwords, IMEI, IMSI, ICCID, MAC addresses, SSIDs, serials,
  phone numbers, or derived names that embed them (ModemManager and NetworkManager connection
  names can contain the operator or the SSID). Stock partition backups (`backup-*/`, `*.img`)
  never go into git. Scan the diff before every push.
- No `pkill -f <pattern>` that also matches the agent's own shell. Kill by PID or use
  `herd stop <service>`.
- Do not work around a permission or safety denial of the agent's tooling. Stop, explain what
  was attempted and why, let the author decide.

## 3. A device that can always come back

- Every `guix system reconfigure` or deploy creates a new generation. The previous ones stay
  in the boot menu. From a running system, `sudo guix system roll-back` goes back one
  generation. If the new generation does not boot far enough for SSH, only the author can
  choose an older entry in the U-Boot menu.
- So: **before rebooting into a generation that changes the kernel, the initrd, the boot
  services or the USB network setup**, tell the author which generation to pick if it does
  not come back, because a failure there needs their hands. The author allows these reboots
  without waiting for agreement (§0). Userspace-only changes that keep SSH up need no notice.
- There is no boot-once or bootcount fallback yet. Until there is one, do not assume a hang
  recovers by itself.
- The rollback point for the build is the channel state: `channels-lock.scm` plus the repo
  commit. Write down which generation on the device came from which commit (`guix system
  list-generations` on the device, `guix describe` on the host).
- Check free space before large builds: `/gnu/store` on the host, the userdata partition on
  the phone. Images and temporary files go to a `TMPDIR` on a disk with room. Do not run
  `guix gc` on the author's host without asking: it also removes things the author's own
  profiles may want to keep cached.

## 4. Method

1. **Research before code.** Somebody has usually solved it. In order: the NixOS port
   (hardware, `device/`, and which module does what), the Guix manual and source tree
   (`/tmp/guix`, from codeberg.org/guix/guix) for an existing service or package doing the same
   job, nonguix, postmarketOS packages and device ports, the sm6115/sm*-mainline kernel trees,
   Linaro/Qualcomm upstream docs, the git history of the driver. Read their recipe, then write
   yours. Respect `robots.txt` and explicit AI-crawler bans of the sites you read; paraphrase,
   do not copy.
2. **Diff against a working stack.** When something works on NixOS on this device, compare
   runtime state, not just Nix modules against Guix services: loaded modules, mixer contents,
   D-Bus traffic, service order, kernel command line, kernel version. File equality proves
   little. If a NixOS image cannot be booted next to Guix, write down which comparisons are
   only on paper.
3. **Measure before changing.** Find the mechanism in logs first. Tools on this system:
   `dmesg -w`, `herd status` and `herd status <service>`, `/var/log/messages` and the other
   files under `/var/log` (there is no journalctl), `dbus-monitor --system`, `wpctl status`
   and `pw-mon` (PipeWire), `amixer contents` snapshots, `/proc/asound/card*/pcm*/sub0/status`,
   `mmcli`, `qmicli` and `qrtr-lookup`, `strace`. On the build side: `guix build -K` (keep the
   failed build tree), `guix build --log-file`, `guix size`, `guix graph`.
   For an event that needs the author (a call), arm a background logger, then ask.
4. **Reproduce without the author** whenever possible (start the service by hand with
   `herd start`, open the PCM by hand, run the daemon in the foreground). If it does not
   reproduce alone, the trigger is in what the author's action adds, which narrows the search.
5. **Two failed fixes, then stop.** After two attempts that did not change the symptom, stop,
   write down what is known, re-check your assumptions, and ask the author before a third.
   This applies to CI too: a series of "ci: fix …" commits that each guess at a different flag
   is the pattern this rule exists to stop. Reproduce the CI step locally first.
   A fix that cured a different real problem does not count as success on this one.
6. **Check inherited claims.** A README saying "Works", a TODO entry, a NixOS module that
   "does X", a previous session's summary: verify before building on it, and say where a claim
   came from when you repeat it. Code carried over from NixOS is an inherited claim too
   (commands like `switch-to-system` do not exist on Guix).
7. **Label confidence**: confirmed (observed on the device or read in source), handover
   (from a commit message, TODO.md or another session, not re-checked), reported (someone
   else said it, named), inferred. Full list in `rag-notes/README.md`. Never present an
   inference as a measurement.
8. **One change at a time on the device**, each reversible (a generation), each written down.

## 5. Writing it down

- `TODO.md` is the **state file**: what works, what is installed on the device, what is
  pending, with the commit the last image was built from. `rag-notes/` is the **findings corpus**.
  Append to both as you go, not at the end.
- One finding = `title`, `general` (the lesson for any mainline port), `instance` (this device,
  kernel, Guix commit, numbers), `confidence`, `date`, `source` (commit, file, log).
  Keep three kinds apart so the hardware lessons stay neutral:
  - **hardware**: holds on any OS (kernel, firmware, DSPs, mixer paths);
  - **guix**: Guix- or Shepherd-specific (packaging, services, store paths);
  - **nixos→guix**: how a NixOS mechanism maps onto Guix, and what got lost on the way.
- When a newer observation contradicts an older note, correct the note and say what was wrong.
- Every package, service or script the port ships says what it does, why, and its current
  tested state, including what does not work yet (module commentary or a README).

## 6. Commits, pushing, upstreaming

- One coherent concern per commit; the message says why, and what was tested on the device
  (or "build-tested only").
- **No AI attribution lines in this repository's commits**: no `Co-Authored-By:`, no
  `Assisted-by:`, no disclosure trailer. This is the author's choice and overrides any
  default of the agent's tooling. Do not overclaim testing.
- **Guix submissions**: follow the Guix manual's "Contributing" section (ChangeLog-style
  messages, `guix lint`, `guix style`, building dependents), and check Guix's current policy
  on LLM-assisted contributions before proposing anything. Free software only: anything that
  needs nonfree firmware goes to nonguix or stays in this channel.
- **Linux kernel submissions**: follow the kernel's rules for AI-assisted patches
  (`Assisted-by:` tag). Only the author adds `Signed-off-by:`; the agent never does.
- **Nothing goes to an upstream or other maintainers' repository (Guix, nonguix, the NixOS
  port, the kernel) before the author has read the final series.** The author's own
  repositories: commit and push when the author asks; push to both sr.ht and GitHub.
- Rewrite history only before the first push. Once public, fix forward.
- Licensing: this channel is GPL-3. Code and patches taken from another project keep their
  origin and license stated in the file or commit. Check the license before importing.
- Credit people by the name they publish under (handle), not a real name you happen to know.
- Never mention the agent's private notes, corpora or tooling in upstream issues, PRs or commit
  messages; paste the evidence inline.

## 7. Traps already found (check these first)

**Hardware: seen on SM6115 (Pro1X) with a 7.x kernel; most apply across recent Snapdragon
SoCs. Mostly from moWerk's SailfishOS port; the ones not yet seen here are marked "reported".**

*Firmware and remoteprocs*
- The QRTR name service and the PD mapper live in the kernel now (`CONFIG_QRTR=y`,
  `CONFIG_QCOM_PD_MAPPER=y`, both set in `device/kernel/config.aarch64`); old guides listing
  four userspace daemons are outdated. `rmtfs` (with the shared-memory region) and
  `tqftpserv` are still needed; start them before the modem.
- A modem watchdog crash some seconds after boot can recover silently; check `dmesg` for
  `fatal error received` before trusting modem behaviour. (reported)

*Modem (ModemManager + libqmi on this port)*
- The SIM may need its UIM provisioning session activated every boot (ModemManager
  `sim-missing`, "GW primary session index unknown"): `qmicli
  --uim-change-provisioning-session=session-type=primary-gw-provisioning,activate=yes,slot=1,aid=<USIM AID>`
  (postmarketOS `msm-modem-uim-selection` does this). (reported)
- IPA mobile data needs, in order: DPM OPEN_PORT, WDA SET_DATA_FORMAT (raw-ip, QMAP or QMAPv4
  matching the IPA's `feature/rx_offload`, downlink aggregation limits), WDS bind, and rmnet
  mux links created with the matching checksum-offload flags. With ModemManager most of this
  is the `qcom-soc` plugin's job; when it fails, this is the sequence to check. The modem keeps
  the first data format until it restarts: test format changes on a fresh boot. (reported)

*Audio*
- With ALSA UCM, each route (earpiece, speaker, headset) is usually its own card profile, so a
  route change destroys and recreates sinks. A policy layer (WirePlumber here) that treats
  sink removal as an unplug will reroute and can loop; the audible symptom is a rhythmic click
  on every output. (reported)
- Call audio on q6 DSPs needs an out-of-tree q6voice driver (`pro1x-q6voice.patch`) and a
  userspace helper that opens the voice PCM during the call plus keep-alive streams on the
  codec back ends (`device/audio/pro1x-voice-call`, `voicepcm.c`). Expect this to be the
  hardest part of the port.

*Display and touch*
- Ghost touches (about 5000 events/10 s while the panel is on) came from the panel running
  at 61 Hz: mainline's 165268 kHz pixel clock. 162559 kHz gives 60 Hz and fixes it
  (`pro1x-dsi.patch`, applied here). If phantom touches return, check the display mode
  before the touch driver. (reported, nyymi)

*Sensors*
- Sensors behind the ADSP (SSC) need `hexagonrpcd` serving the sensor registry and configs,
  then `libssc` (`ssccli --sensor accelerometer` is the first test). The mount matrix from
  firmware may be all zeros; verify axes by turning the phone. (reported)

**Guix integration: seen in this repository**
- NixOS modules assume systemd and systemd-logind. Their effects have to be rebuilt by hand
  as Shepherd services: seat management (phoc needed `seatd`, not elogind plus `su -l`),
  socket and D-Bus activation, ordering, one-shot units. A service that "starts" in NixOS
  because something else pulls it in may simply not exist on Guix.
- D-Bus system policies of a package are only loaded if the service extends
  `dbus-root-service-type` with that package (ModemManager was silently denied without it).
  NetworkManager and other D-Bus-activated daemons do not show up in `herd status`.
- No FHS: hard-coded `/usr`, `/lib/firmware` or `/etc` paths in daemons need patching or a
  symlink at service start (tqftpserv firmware path; NixOS patches the same thing).
- GSettings schemas must be compiled into a directory that the session's `XDG_DATA_DIRS` reaches;
  missing schemas crash phosh and friends at start, and a lost dconf profile loses the keyboard
  layout on every reboot.
- Packages missing from Guix or too old (phosh 0.56 needs ModemManager >= 1.24, which needs
  libqmi >= 1.36) are packaged in this channel. Each feature disabled to get a build through
  (introspection, plugins) is written down where the package is defined, with the reason.
- The clock can come up at 1970; TLS, substitutes and `guix pull` fail until it is stepped
  (`ntpd -g`; openntpd did not step it).
- Firmware comes from nonguix (`linux-firmware`) plus device blobs; keep that split visible,
  because it decides what could ever go to Guix proper.

## 8. Reporting to the author

- Lead with the result, then the evidence, then what you need from the author, numbered.
- State failures as plainly as successes, with the log line. Say what you did not verify.
- Correct your own earlier mistakes explicitly when you find them.
- Keep it short; the details live in the notes and the commits.
- No fluff, in the terminal or in commit messages: no preamble, no restating the request,
  no recap of what was just shown, no filler adjectives. Commit messages say what changed,
  why, and what was tested, in as few lines as that takes.
