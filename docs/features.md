# GNU Guix System on the F(x)tec Pro¹x

Near-mainline Linux, U-Boot and GNU Guix System (Shepherd, no systemd)
on the Pro¹x.  No Android, vendor kernel or Halium underneath; nonfree
parts are firmware only.  Work in progress.

<!-- picture or video: to come -->

## Sessions

Chosen at the text login (tuigreet; remembers user and session):

- **Sway**: tiling desktop for the keyboard, landscape.
- **Phosh**: phone shell with GNOME Settings, Calls, Chatty, Snapshot.
- **Sxmo on Sway**: starts; needs superd, not packaged yet.

## Works (observed 2026-10-30, Linux 7.1)

Display, touch, GPU; keyboard with Fn layer and backlight; slider
(keyboard out: landscape locked); Wi-Fi; Bluetooth (audio to it untested);
USB SSH; speaker, volume keys;
both cameras (Snapshot); auto-rotation; battery state; SIM and data on
3G; vibration and ringtone; idle dimming; double tap to wake; Tailscale.

## Not yet

LTE, GPS, calls, SMS, earpiece, headphones, microphones, proximity and
light sensors, suspend.  Speaker pops at login.  Details:
[README](../README.md#port-status), [TODO.md](../TODO.md).

## How it is run

The phone's whole system is `~/.config/guix/config.scm`, which inherits
the port's system ([configure.md](configure.md)).  Your PC builds it and
installs it over USB or Tailscale; each update is a boot-menu entry you
can go back to ([update.md](update.md)).

[install.md](install.md) · [usage.md](usage.md) · [configure.md](configure.md) ·
[update.md](update.md) · [channels.md](channels.md) ·
[troubleshoot.md](troubleshoot.md)
