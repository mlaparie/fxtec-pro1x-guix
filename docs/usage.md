# Using the phone

## Sessions

Pick one at tuigreet, the text login (it remembers your last user and
session; F12 for shutdown and reboot):

- **1 Sway**: Super (yellow arrows) is the modifier.  Super+Return
  terminal, Super+q quick actions, Super+m launcher, Super+Tab window
  switcher, Super+i on-screen keyboard, Super+Ctrl+l lock, Super+b bar,
  Super+Shift+q close, Super+Ctrl+h all key bindings, Super+Shift+e exit.
- **2 Phosh**: swipe up for the app drawer, down from the top for quick
  settings.
- **3 Sxmo on Sway**: not usable yet (superd missing).

## Keyboard and slider

- Keyboard out: landscape, rotation locked, keyboard light on until 60 s
  without a key.  Keyboard in: auto-rotation (if on in quick actions).
- Fn layer (F(x) key): F1-F12, media, brightness, page keys; layout in the
  [README](../README.md#keyboard).

## Screen

| | |
|---|---|
| power key | screen off / on; held: power menu (Sway) |
| both volume keys together (Sway) | lock, keyboard closed or not |
| double tap, Esc | screen on, while it is off (not in a pocket) |
| idle 150 s | dims to 20% |
| idle 180 s | screen off; locked 2 min later |
| keyboard slid in / out | portrait / landscape |
| rotation (Phosh tile, Sway quick actions) | sensor rotation on or off |
| Sway: edge swipes | top: quick actions, bottom: on-screen keyboard, right: launcher, left: window switcher |

Times and levels are options in `config.scm` ([configure.md](configure.md)).

## Sway's menus

Quick actions (top swipe, Super+q), the launcher (right swipe, Super+m),
the window switcher (left swipe, Super+Tab) and the power menu (power key
held) are lists: type to filter, arrows to move, Enter to choose, Esc to
close; the same swipe again closes them.  With a menu open, a short press
of the power key is its Enter, a long one closes it.  In quick actions:

- Enter toggles a line (Wi-Fi, Bluetooth, torch…) or opens its choices
  (mobile data, operator, CPU mode, charge limit, keyboard layout…);
- Right and Left step brightness and volume, Right opens the Wi-Fi and
  Bluetooth tools;
- the Notifications line opens them, with the text beside (landscape) or
  below (portrait); Del dismisses one;
- the GPU monitor line opens nvtop (GPU load, clock, GPU time per app),
  and CPU mode's choices bpytop, each in its own window.

Settings changed there last until reboot (operator, CPU mode, charge
limit) unless the line says otherwise; the lasting ones are in
`config.scm`.

## Calls and messages

Calls (GNOME Calls), SMS and MMS (Chatty) work.  In a call, the mute
button does nothing yet (the other side still hears you).  On 4G, calls go
through VoLTE (81voltd), which networks without 2G/3G fallback for calls
need; outgoing ones often fall back to 3G and take 20–40 s to ring.

MMS need your operator's MMS settings in Chatty (MMSC, MMS APN, proxy with
its port).  Most operators use the data APN for MMS too; check before
entering a separate one.  If yours really has a separate MMS APN, a
reminder notification appears for waiting MMS and the "Fetch MMS" app
downloads them (mobile internet pauses briefly).

## Network

- Wi-Fi and mobile data: Phosh quick settings or GNOME Settings; `nmcli`
  in a terminal; in Sway, quick actions.  Mobile data works on 3G and 4G.
  For WPA2 Enterprise (eduroam…): `nm-connection-editor`.
- USB cable to a PC: the phone is `172.16.42.1` (`ssh user@172.16.42.1`).
- Tailscale, if in your configuration: `sudo tailscale up` once.

## Passwords

- Your password (login, lock screen, sudo): `passwd`.  The first boot has
  `123456`; change it then, and again after a reflash (the backup does not
  carry it).
- Another account's, as root: `sudo passwd NAME`.
- The disk passphrase (encrypted phones): it is in the LUKS header on
  `/dev/loop0`, and `cryptsetup luksChangeKey /dev/loop0` changes it (`sudo
  guix shell cryptsetup -- cryptsetup luksChangeKey /dev/loop0`; not yet
  tried on the phone).  The prompt at boot has the US layout.

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
