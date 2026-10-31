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

## Phone comforts

- Double tap or Esc wakes the screen; not while in a pocket
  (proximity sensor).
- Screen off and touch disabled near the face during calls (Sway).
- Portrait with the keyboard closed, landscape with it out; optional
  auto-rotation that ignores quick tilts.
- On-screen keyboard (stevia) when the keyboard is closed, never when it
  is out; Super key in its terminal layout; a short vibration per key
  (config.scm).
- Dim, blank and lock after idle (150 s, 180 s, +2 min; config.scm).
- Dark apps and shell by default (color-scheme in config.scm).
- Charge limit (85/80 %), shown in quick actions.
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
  notifications with a preview, camera, lock, charge limit; Right on
  Wi-Fi or Bluetooth opens a picker (nmcli-fzf, bluetuith).
- Status bar: the full list in landscape, the essentials in portrait;
  Super+b hides it.
- Lock with Ctrl+Super+l or both volume keys together.
- Lock screen (gtklock): clock, GNU Guix banner, unread notifications
  per app; an on-screen keyboard while the keyboard is closed (numpad in
  landscape), dark or light in config.scm.
- Notifications briefly light a dark screen, dimly.
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
