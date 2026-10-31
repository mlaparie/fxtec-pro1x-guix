# Using the phone

## Sessions

Pick one at tuigreet, the text login (it remembers your last user and
session; F12 for shutdown and reboot):

- **1 Sway**: Super (yellow arrows) is the modifier.  Super+Return
  terminal, Super+q quick actions, Super+m launcher, Super+Tab window
  switcher, Super+Shift+q close, Super+Ctrl+h all key bindings,
  Super+Shift+e exit.
- **2 Phosh**: swipe up for the app drawer, down from the top for quick
  settings.
- **3 Sxmo on Sway**: not usable yet (superd missing).
- **4 Sway (plain)**: Sway without SwayFX's blur, to compare speed.

## Keyboard and slider

- Keyboard out: landscape, rotation locked, keyboard light on until 60 s
  without a key.  Keyboard in: auto-rotation (if on in quick actions).
- Fn layer (F(x) key): F1-F12, media, brightness, page keys; layout in the
  [README](../README.md#keyboard).

## Screen

| | |
|---|---|
| power key | screen off / on |
| both volume keys together (Sway) | lock, keyboard closed or not |
| double tap, Esc | screen on, while it is off (not in a pocket) |
| idle 150 s | dims to 20% |
| idle 180 s | screen off; locked 2 min later |
| keyboard slid in / out | portrait / landscape |
| rotation (Phosh tile, Sway quick actions) | sensor rotation on or off |
| Sway: edge swipes | top: quick actions, bottom: on-screen keyboard, right: launcher, left: window switcher |

Times and levels are options in `config.scm` ([configure.md](configure.md)).

## Calls and messages

Calls (GNOME Calls), SMS and MMS (Chatty) work.  In a call, the speaker
button and the mute button do nothing yet (the call stays on the earpiece,
and the other side still hears you).

MMS need your operator's MMS settings in Chatty (MMSC, MMS APN, proxy with
its port).  Most operators use the data APN for MMS too; check before
entering a separate one.  If yours really has a separate MMS APN, a
reminder notification appears for waiting MMS and the "Fetch MMS" app
downloads them (mobile internet pauses briefly).

## Network

- Wi-Fi and mobile data: Phosh quick settings or GNOME Settings; `nmcli`
  in a terminal; in Sway, quick actions.  Mobile data works on 3G; LTE
  seen, not confirmed.
- USB cable to a PC: the phone is `172.16.42.1` (`ssh user@172.16.42.1`).
- Tailscale, if in your configuration: `sudo tailscale up` once.

## Changing the system: the loop

1. Edit `~/.config/guix/config.scm` (on the phone, or on the PC and copy it
   over).
2. Deploy from the PC: `bash scripts/deploy.sh` ([update.md](update.md)).
3. Log out and in for session changes; reboot for kernel changes.
4. Broken?  `sudo guix system roll-back`, or volume-down at power-on and an
   older entry.

Your Sway and foot files add to the port's, which follow deploys
([configure.md](configure.md#files-outside-configscm)); other home files
can be managed from `config.scm` with Guix Home ([home.md](home.md)).
