# Configuring

The phone's system is `~/.config/guix/config.scm`, built from the
channels in `~/.config/guix/channels.scm`.  Start from the shipped copies:

```sh
mkdir -p ~/.config/guix
cp /etc/guix/config.scm /etc/guix/channels.scm ~/.config/guix/
```

Apply changes with a deploy or a reconfigure ([update.md](update.md)).

## config.scm

It inherits the port's system; the port's fixes come with the channel,
your changes stay here.  Each field (`services`, `packages`, ...) appears
once, so combine changes in one expression:

```scheme
(use-modules (gnu)
             (btv tailscale)                    ; from the tailscale channel
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x system mobile))

(define base (pro1x-mobile-operating-system))

(operating-system
  (inherit base)
  (timezone "Europe/Paris")
  (packages (cons tailscale (operating-system-packages base)))
  (services
   (cons (service tailscale-service-type)
         (modify-services (operating-system-user-services base)
           (pro1x-keyboard-service-type
            config => (pro1x-keyboard-configuration
                       (inherit config) (backlight-timeout 120)))
           (pro1x-hardware-service-type
            config => (pro1x-hardware-configuration
                       (inherit config) (dim-after 90) (dim-level 20)))))))
```

## Port options

| field | default | |
|---|---|---|
| keyboard `backlight-timeout` | `60` | seconds without a key before the keyboard light goes off; `#f` never |
| keyboard `xkb-layout`, `xkb-variant` | `"us"`, `"intl"` | session keyboard layout |
| hardware `dim-after` | `150` | idle seconds before the panel dims; `#f` never |
| hardware `dim-level` | `20` | dim level, % of maximum |
| hardware `blank-after` | `180` | idle seconds before the panel turns off |
| hardware `lock-after` | `120` | seconds after blanking before locking; `#f` never |
| hardware `double-tap-wake?` | `#t` | double tap on the touchscreen wakes the panel |
| hardware `color-scheme` | `'prefer-dark` | `'default` for light apps and shell |
| hardware `keyboard-haptics?` | `#t` | a short vibration per on-screen key |
| hardware `keyboard-languages` | `'()` | word completion dictionaries besides English: `'("fr")`, any of `"fr"` `"de"` `"it"`; quick actions chooses which to combine, or off |
| hardware `keyboard-layouts` | `'("us")` | on-screen keyboard layouts, independent of the dictionaries; chosen in quick actions or with the keyboard's layout key |
| hardware `lock-keyboard` | `'dark` | the Sway lock screen's keyboard, `'dark` or `'light` |
| hardware `notification-leds` | blue messages, purple missed calls, white bell | list of `(EVENT COLOUR)` or `(EVENT COLOUR PERIOD-MS)`; colours `"red"` … or `"#RRGGBB"` |
| hardware `charging-led`, `charged-led` | `"#FFA000"`, `"#00FF00"` | breathing while charging, steady when full or held; `#f` off |
| hardware `low-battery-led`, `low-battery-level` | `"#FF4000"`, `15` | a short blip every 4 s at or below that % |
| hardware `charge-limit`, `charge-resume` | `85`, `80` | stop charging at 85%, charge again at 80%; `#f` charges to full.  Quick actions (Charge limit line) override it until the next reboot, marked "(until reboot)" |
| hardware `torch-timeout` | `60` | seconds before a torch left on is switched off; `#f` never |
| hardware `wake-on` | `'(calls sms)` | what may wake the phone from suspend besides its keys and alarms: `'calls`, `'sms` (Chatty's text messages); internet chats cannot (the network is not a wake source) |
| hardware `cpu-mode` | `'auto` | the CPU's energy mode: `'auto` (balanced; battery while the screen is off or the battery is at 20 % or less), `'battery` (schedutil, capped at 1.31/1.40 GHz), `'balanced` (schedutil, dynamic), `'performance` (top frequency).  Quick actions (CPU mode line) override it until the next reboot, marked "(until reboot)" |
| hardware `shake-torch?` | `#t` | shaking the phone twice runs `shake-action`, locked or not |
| hardware `shake-action` | `'torch` | `'torch` toggles the torch; a string is a shell command, run in Sway (over the lock screen for `lock-screen-apps`) |
| hardware `portrait-apps` | Calls, Camera (`org.pro1x.Camera`), Snapshot | app_ids (`swaymsg -t get_tree`) that turn the panel to portrait while focused (Sway) |
| hardware `landscape-apps` | none | the same, landscape |
| hardware `fullscreen-apps` | Calls, Camera, Snapshot | app_ids made fullscreen when they open (Sway) |
| hardware `lock-screen-apps` | Calls, Camera, Snapshot | app_ids allowed to open over the lock screen: an incoming call, the camera button's triple press, `shake-action`; the session unlocks for them and locks again when they lose the focus |
| hardware `camera-triple-press` | `"pro1x-camera-app"` | shell command for a triple press of the camera button (default: the camera; not while the proximity sensor reads near); a press in the camera app (or Snapshot) takes a picture, a single press elsewhere is a left click where the pointer is (a right click with Fn held); held, the touchscreen is a touchpad moving the pointer, and with Super held too a window drag |
| hardware `display-top-gap`, `display-bottom-gap` | `0` | rows blacked out, touch adjusted |
| hardware `serial-enable?` | `#f` | USB serial rescue console |

`blank-after` and `lock-after` are the defaults of the GSettings keys that
GNOME Settings (blank) and Phosh Mobile Settings ("Automatic screen lock
delay") show and change; a value set there wins, in Phosh and in Sway.
`color-scheme` too.

Keyboard: `pro1x-keyboard-configuration` in `(fxtec-pro1x services
keyboard)`; hardware: `pro1x-hardware-configuration` in `(fxtec-pro1x
services hardware)`.

Root SSH: deploys keep the PC's key in root's keys whatever this file
says; `#:root-ssh-keys` matters only for root SSH after an on-phone
reconfigure.

## Files outside config.scm

The port's Sway, bar and foot settings follow each deploy; your files add
to them, and a later setting wins:

| file | |
|---|---|
| `~/.config/sway/config` | includes the port's `/etc/sway/pro1x.d/desktop.conf`, then your lines; a `bindsym` for a key the port binds replaces it |
| `~/.config/foot/foot.ini` | includes the port's foot settings, then yours |
| `~/.config/i3status-rust/` | none by default: the bar uses the port's blocks; `config.toml` (landscape) or `portrait.toml` here replaces them (copy from `/run/current-system/profile/share/pro1x-sway/`) |
| `~/.config/phoc/phoc.ini` | Phosh's scale (copy `/etc/phoc.ini`, set `scale=`); Phosh does not save the one picked in Settings |

Accounts made before 2026-10-31 have full copies instead: replace
`~/.config/sway/config` and `foot.ini` with the files in
`/run/current-system/profile/share/pro1x-sway/` (`config`, `foot-user.ini`)
and remove `~/.config/i3status-rust/config.toml` to follow the port.

GNOME Settings choices live in dconf and survive updates.

## channels.scm

guix, nonguix and fxtec-pro1x.  **guix and nonguix are pinned** to the
tested commits: no substitute server builds this channel's packages, so
other commits mean building the kernel and Phosh yourself, for hours.

Add channels to the list, e.g. Tailscale:

```scheme
(channel
 (name 'tailscale)
 (url "https://github.com/umanwizard/guix-tailscale")
 (branch "main")
 (introduction
  (make-channel-introduction
   "52e82318f282c555757ef077d93a685fda97565d"
   (openpgp-fingerprint
    "9E53 FC33 B832 8C74 5E7B  31F7 0226 C10D 7877 B741"))))
```

Then, after the next update, `sudo tailscale up` once.
