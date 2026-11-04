# GNU Guix System on the F(x)tec Pro¹x

Near-mainline Linux, U-Boot and GNU Guix System (Shepherd, no systemd).
No Android, vendor kernel or Halium; nonfree parts are firmware only.
Work in progress.

## Sessions

Picked at the text login (tuigreet, remembers user and session):

- **Sway**: keyboard-first desktop, made for the phone (below).
- **Phosh**: phone shell (GNOME Settings, Calls, Chatty, Snapshot).
- **Sxmo on Sway**: starts; needs superd, not packaged yet.

## Works (2026-10-31, Linux 7.1)

Display, touch, GPU; keyboard, Fn layer, backlight; Wi-Fi; Bluetooth
(audio too); USB SSH; speaker, earpiece, microphones; both cameras
(Snapshot, early); accelerometer, proximity sensor; battery and charge
limit; SIM, SMS, MMS, calls (earpiece), mobile data; vibration;
Tailscale.

`main` is on Linux 7.3 since 2026-11-04 (the phone since 2026-11-03), merged before
the checks below; tag `pre-7.3` is the last `main` on 7.1.  Both cameras work on 7.3
too, early.  Not yet checked on 7.3: calls, audio, suspend, deep sleep,
charging.

## Phone comforts

- Double tap or Esc wakes the screen; not while in a pocket
  (proximity sensor).
- Screen off and touch disabled near the face during calls (Sway).
- Portrait with the keyboard closed, landscape with it out; optional
  auto-rotation that ignores quick tilts.
- On-screen keyboard (stevia): in Sway by hand (bottom swipe, quick actions),
  hidden when the keyboard slides out; in Phosh when a text field needs it
  with the keyboard closed; a bar of shortcut keys above the first row on
  every layout (Super, Ctrl, arrows…); a short vibration per key (config.scm).
- Word completion on the on-screen keyboard: English, plus French, German or
  Italian if added in config.scm.  Quick actions turns it off or combines the
  dictionaries you tick, whatever the layout; layouts are separate
  (keyboard-layouts).
- LibreWolf, IceCat and Firefox fit portrait: narrower window, and our signed
  extension sends a mobile user agent in portrait only, so sites offer their
  mobile layout.  It makes the browser stand out in portrait next to
  resistFingerprinting.
- Dim, blank and lock after idle (150 s, 180 s, +2 min; config.scm).
- Dark apps and shell by default (color-scheme in config.scm).
- Charge limit (85/80 %) set in config.scm; quick actions override it until reboot.
- Notification LED: blue for messages, purple for missed calls, white
  for the terminal bell (config.scm); breathing yellow
  while charging, green when full or held, red blip on low battery.
- Keyboard backlight only while slid out, off after 60 s idle.
- Speaker pops at login removed.
- Wi-Fi, mobile data and rotation settings kept across reboots;
  keep-screen-on (caffeine) is not.

## Sway on the phone

- Edge swipes: top, quick actions; bottom, on-screen keyboard; right,
  app launcher; left, window switcher.  Same swipe again closes.
- Quick actions (Super+q): toggles with Left/Right, battery, network
  details (2G/3G/4G), mobile data modes and roaming, SIM PIN entry,
  notifications with a preview, camera, lock, charge limit, word completion,
  keyboard layout; Right on Wi-Fi or Bluetooth opens a picker (nmcli-fzf,
  bluetuith).  A change shows on its line at once, and "failed" in red if it
  did not work.
- App launcher (Super+m): after the app, the workspace to open it on, the
  current one first, so Enter or power twice opens it here.
- The bottom swipe keeps the focused window focused.
- Status bar: the full list in landscape, the essentials in portrait;
  Super+b hides it.
- Lock with Ctrl+Super+l or both volume keys together.
- Power key: short press screen off/on, held a power menu (power off,
  reboot, lock, suspend…).  In the menus (quick actions, launcher, window
  switcher, power), the volume keys move and the power key confirms, with
  the keyboard closed.
- Lock screen (gtklock): clock, GNU Guix banner, battery and CPU mode, unread
  notifications per app; an on-screen keyboard while the keyboard is closed
  (numpad in landscape), dark or light in config.scm.  It redraws itself when
  the phone turns.
- Notifications briefly light a dark screen, dimly.
- An app allowed over the lock screen (a call, an alarm, the camera button's
  triple press) really unlocks the session behind it: bindings, keyboards,
  pointers, menus and gestures stay off meanwhile, and the phone locks again
  when it closes or loses the focus.
- Incoming calls show over the lock screen (not yet tried with a call);
  Calls and the camera open fullscreen in portrait, the previous
  rotation comes back after.
- Chatty and Calls run in the background.
- Volume and brightness keys show a bar for a second (grey when muted).
- Screenshots: Fn+Alt+P (region: with Ctrl); camera button opens
  Snapshot, or takes a picture in it.
- SwayFX: blur behind the 90 % opaque foot (Iosevka); foot server for
  fast menus and terminals.
- The port's Sway, bar and foot settings follow updates; your own files
  add to them ([configure.md](configure.md#files-outside-configscm)).

## Not yet

LTE, GPS, speakerphone and mute in calls, headphones, light sensor,
suspend.  Details: [README](../README.md#port-status),
[TODO.md](../TODO.md).

## How it is run

The phone's whole system is `~/.config/guix/config.scm`, inheriting the
port's ([configure.md](configure.md)).  The PC builds it and installs it
over USB or Tailscale; each update is a boot-menu entry
([update.md](update.md)).

[install.md](install.md) · [usage.md](usage.md) · [configure.md](configure.md) ·
[update.md](update.md) · [channels.md](channels.md) ·
[troubleshoot.md](troubleshoot.md)
