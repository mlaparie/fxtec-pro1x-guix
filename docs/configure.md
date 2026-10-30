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
| hardware `dim-after` | `30` | idle seconds before the panel dims; `#f` never |
| hardware `dim-level` | `20` | dim level, % of maximum |
| hardware `blank-after` | `60` | idle seconds before the panel turns off |
| hardware `lock-after` | `120` | seconds after blanking before locking; `#f` never |

`blank-after` and `lock-after` are the defaults of the GSettings keys that
GNOME Settings (blank) and Phosh Mobile Settings ("Automatic screen lock
delay") show and change; a value set there wins, in Phosh and in Sway.
| hardware `double-tap-wake?` | `#t` | double tap on the touchscreen wakes the panel |
| hardware `torch-timeout` | `60` | seconds before a torch left on is switched off; `#f` never |
| hardware `charge-limit`, `charge-resume` | `85`, `80` | stop charging at 85%, charge again at 80%; `#f` charges to full.  `sudo herd stop pro1x-charge-limit` charges to full once |
| hardware `display-top-gap`, `display-bottom-gap` | `0` | rows blacked out, touch adjusted |
| hardware `serial-enable?` | `#f` | USB serial rescue console |

Keyboard: `pro1x-keyboard-configuration` in `(fxtec-pro1x services
keyboard)`; hardware: `pro1x-hardware-configuration` in `(fxtec-pro1x
services hardware)`.

Root SSH: deploys keep the PC's key in root's keys whatever this file
says; `#:root-ssh-keys` matters only for root SSH after an on-phone
reconfigure.

## Files outside config.scm

Edited in place for now (Guix Home is planned):

| file | |
|---|---|
| `~/.config/sway/config` | Sway; device settings are in `/etc/sway/config.d/pro1x.conf` |
| `~/.config/phoc/phoc.ini` | Phosh's scale (copy `/etc/phoc.ini`, set `scale=`); Phosh does not save the one picked in Settings |
| `~/.config/foot/foot.ini` | terminal |

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
