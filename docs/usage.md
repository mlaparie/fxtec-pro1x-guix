# Using the phone

## Sessions

Pick one at tuigreet, the text login (it remembers your last user and
session; F12 for shutdown and reboot):

- **1 Sway**: Super (yellow arrows) is the modifier.  Super+Return
  terminal, Super+m launcher, Super+Tab window switcher, Super+Shift+q
  close, Super+Ctrl+h key bindings, Super+Shift+e exit.
- **2 Phosh**: swipe up for the app drawer, down from the top for quick
  settings.
- **3 Sxmo on Sway**: not usable yet (superd missing).

## Keyboard and slider

- Keyboard out: landscape, rotation locked, keyboard light on until 60 s
  without a key.  Keyboard in: auto-rotation (if on in quick settings).
- Fn layer (F(x) key): F1-F12, media, brightness, page keys; layout in the
  [README](../README.md#keyboard).

## Screen

| | |
|---|---|
| power key | screen off / on |
| double tap | screen on, while it is off |
| idle 60 s | dims to 20% |
| idle 5 min | screen off, then locked (lock untested) |
| rotation tile (quick settings) | tap: lock or unlock auto-rotation; long press: auto or manual |

Times and levels are options in `config.scm` ([configure.md](configure.md)).
GNOME Snapshot always stays in portrait.

## Network

- Wi-Fi and mobile data: Phosh quick settings or GNOME Settings; `nmcli`
  in a terminal.  Mobile data works on 3G; LTE not yet.
- USB cable to a PC: the phone is `172.16.42.1` (`ssh user@172.16.42.1`).
- Tailscale, if in your configuration: `sudo tailscale up` once.

## Changing the system: the loop

1. Edit `~/.config/guix/config.scm` (on the phone, or on the PC and copy it
   over).
2. Deploy from the PC: `bash scripts/deploy.sh` ([update.md](update.md)).
3. Log out and in for session changes; reboot for kernel changes.
4. Broken?  `sudo guix system roll-back`, or volume-down at power-on and an
   older entry.

Files Guix does not manage yet (Sway, foot, phoc scale) are edited in
place in `~/.config` ([configure.md](configure.md#files-outside-configscm)).
