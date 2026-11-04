;;; fxtec-pro1x/system/common.scm — what the Pro¹x systems share
;;;
;;; Root SSH by key, for guix deploy from a PC (scripts/deploy.sh): the
;;; key pair is made on the PC when the phone is flashed (scripts/flash.sh,
;;; ~/.ssh/pro1x-guix).  A system built with ROOT-SSH-KEYS (public key
;;; files) lets root in with them and puts the first one in new users'
;;; homes as ~/.ssh/pro1x-guix.pub, so the owner's own configuration can
;;; refer to it.
;;;
;;; /etc/guix/config.scm and /etc/guix/channels.scm: starting files for the
;;; phone's owner (channels: see (fxtec-pro1x services channels)).
;;; config.scm inherits the port's system from the channel, so guix pull still
;;; brings the port's fixes; root SSH is off in it until the owner
;;; uncomments one line (opt-in), and it holds no key, so it can be shared
;;; as a dotfile.
;;;
;;; State: template evaluated on the PC for the three systems, with and
;;; without the key line; not yet used on the phone.

(define-module (fxtec-pro1x system common)
  #:use-module (fxtec-pro1x services channels)
  #:use-module (gnu packages linux)        ; procps
  #:use-module (gnu packages glib)         ; dbus
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:export (pro1x-root-authorized-keys
            pro1x-root-key-skeletons
            pro1x-user-config-service
            pro1x-reload-bus-service))

(define (pro1x-root-authorized-keys keys)
  "Return openssh authorized-keys entries letting root in with KEYS, a list
of public key files."
  (if (null? keys)
      '()
      `(("root" ,@keys))))

(define (pro1x-root-key-skeletons keys)
  "Return skeleton entries putting the first of KEYS in new homes as
~/.ssh/pro1x-guix.pub."
  (if (null? keys)
      '()
      `((".ssh/pro1x-guix.pub" ,(car keys)))))

(define (pro1x-user-config module procedure)
  "Return the text of /etc/guix/config.scm for the system that PROCEDURE, a
symbol exported by MODULE, a list of symbols, returns."
  (string-append
   ";;; /etc/guix/config.scm — starting point for your own configuration of
;;; this phone, written by the fxtec-pro1x channel.  To use it:
;;;
;;;   cp /etc/guix/config.scm /etc/guix/channels.scm ~/.config/guix/
;;;   guix pull                # then log out and back in once
;;;   sudo guix system reconfigure ~/.config/guix/config.scm
;;;
;;; The port's system comes from the channel, so guix pull brings its fixes;
;;; your changes stay in this file.

(use-modules (gnu)
             " (with-output-to-string (lambda () (write module))) ")

(define base
  (" (symbol->string procedure) "
   ;; Root SSH login by key lets `guix deploy` from a PC update this phone
   ;; (scripts/deploy.sh in the fxtec-pro1x-guix repository).  It is off
   ;; until you uncomment the line below.  ~/.ssh/pro1x-guix.pub is the
   ;; PC's key, put in your home when the phone was flashed; the path is
   ;; relative to this file.
   ;; #:root-ssh-keys (list (local-file \"../../.ssh/pro1x-guix.pub\"))
   ))

(operating-system
  (inherit base)
  ;; Your changes, for example:
  ;; (timezone \"Europe/Paris\")
  ;; (packages (cons (specification->package \"htop\")
  ;;                 (operating-system-packages base)))
  ;; (services (cons (service some-service-type)
  ;;                 (operating-system-user-services base)))
  ;; The port's options; needs (fxtec-pro1x services hardware) in use-modules,
  ;; and only one services field:
  ;; (services
  ;;  (modify-services (operating-system-user-services base)
  ;;    (pro1x-hardware-service-type
  ;;     config => (pro1x-hardware-configuration
  ;;                (inherit config)
  ;;                Every option, with its default; uncomment to change.
  ;;                Screen: seconds without input (#f: never), dim level in % of maximum.
  ;;                (dim-after 150)
  ;;                (dim-level 20)
  ;;                (blank-after 180)
  ;;                Lock this many seconds after blanking (0: at once; #f: never).
  ;;                (lock-after 120)
  ;;                Suspend this many seconds after blanking, locking first (#f: never; Sway).
  ;;                (auto-suspend #f)
  ;;                Double tap on the touchscreen wakes the panel.
  ;;                (double-tap-wake? #t)
  ;;                Light or dark apps and shell: 'prefer-dark or 'default (light).
  ;;                (color-scheme 'prefer-dark)
  ;;                Rows to black out at the panel's top and bottom.
  ;;                (display-top-gap 0)
  ;;                (display-bottom-gap 0)
  ;;                On-screen keyboard: word completion dictionaries besides English, any of
  ;;                \"fr\" \"de\" \"it\" (no Spanish in Guix); quick actions combines them, or off.
  ;;                (keyboard-languages '())
  ;;                Its layouts (xkb names), independent of the dictionaries; quick actions
  ;;                chooses among them.
  ;;                (keyboard-layouts '(\"us\"))
  ;;                A short vibration on each key.
  ;;                (keyboard-haptics? #t)
  ;;                At each Sway login: Firefox-family browsers fitted to portrait, with a
  ;;                mobile user agent there; #f stops it, what it added stays.
  ;;                (browser-fit? #t)
  ;;                The lock screen's on-screen keyboard: 'dark or 'light.
  ;;                (lock-keyboard 'dark)
  ;;                Charging: stop at this % (#f: charge to full), again at or below the second;
  ;;                quick actions overrides until reboot.  Stay awake while charging (7.3 kernel).
  ;;                (charge-limit 85)
  ;;                (charge-resume 80)
  ;;                (charging-awake? #t)
  ;;                CPU: 'auto, 'battery, 'balanced or 'performance; quick actions overrides
  ;;                until reboot.
  ;;                (cpu-mode 'auto)
  ;;                What wakes the phone from suspend, besides its keys and alarms.
  ;;                (wake-on '(calls sms))
  ;;                Torch off after this many seconds (#f: never).
  ;;                (torch-timeout 60)
  ;;                Shaking twice: 'torch, or a shell command (a string).
  ;;                (shake-torch? #t)
  ;;                (shake-action 'torch)
  ;;                The camera button's triple press: a shell command.
  ;;                (camera-triple-press \"pro1x-camera-app\")
  ;;                Apps, by Wayland app_id (swaymsg -t get_tree): portrait or landscape while
  ;;                focused, fullscreen when opened, allowed over the lock screen.
  ;;                (portrait-apps '(\"org.gnome.Calls\" \"org.gnome.Snapshot\"))
  ;;                (landscape-apps '())
  ;;                (fullscreen-apps '(\"org.gnome.Calls\" \"org.pro1x.Camera\" \"org.gnome.Snapshot\"))
  ;;                (lock-screen-apps '(\"org.gnome.Calls\" \"org.pro1x.Camera\"))
  ;;                Notification LED: (EVENT COLOUR) or (EVENT COLOUR BLINK-MS); colours \"red\"
  ;;                \"green\" \"blue\" \"white\" or \"#RRGGBB\"; unlisted events keep feedbackd's.  More
  ;;                events: \"message-missed-email\", \"message-missed-notification\",
  ;;                \"notification-missed-generic\", \"battery-caution\".
  ;;                (notification-leds
  ;;                 '((\"message-missed-sms\" \"blue\") (\"message-missed-instant\" \"blue\")
  ;;                   (\"phone-missed-call\" \"#8000FF\") (\"bell-terminal\" \"white\")))
  ;;                Battery LED: breathing while charging, steady when full or at the limit, a
  ;;                blip every 4 s at or below low-battery-level %; #f turns one off.
  ;;                (charging-led \"#FFA000\")
  ;;                (charged-led \"#00FF00\")
  ;;                (low-battery-led \"#FF4000\")
  ;;                (low-battery-level 15)
  ;;                LED while blank but not locked: (COLOUR LEVEL), level 0-255, or #f.
  ;;                (unlocked-led '(\"white\" 6))
  ;;                Console and debugging: fbcon rotation (0-3), USB serial console on ttyGS0,
  ;;                verbose kernel log.
  ;;                (console-rotation #f)
  ;;                (serial-enable? #f)
  ;;                (verbose? #f)
  ;;                )))
  ;;    The port's other services, also inside modify-services.  Each needs its module
  ;;    in use-modules: (fxtec-pro1x services keyboard), and usb-network, modem, sensors,
  ;;    boot, audio.
  ;;    (pro1x-boot-menu-service-type
  ;;     config => (pro1x-boot-menu-configuration
  ;;                (inherit config)
  ;;                U-Boot's menu at each boot.  Any whole number: seconds before it boots
  ;;                the current system; 0: no menu, it boots at once, so an older generation
  ;;                cannot be chosen; -1: no autoboot, it waits for a key, after a crash or
  ;;                a remote reboot too.  Takes effect at the next deploy, then boot; no reflash.
  ;;                (delay 15)
  ;;                Older generations in that menu, besides the current one.  Leave at 4:
  ;;                the same number is built into U-Boot, and changing that one needs a
  ;;                new flash.
  ;;                (generations 4)))
  ;;    (pro1x-boot-success-service-type
  ;;     config => (pro1x-boot-success-configuration
  ;;                (inherit config)
  ;;                Marks the boot slot as good after a boot.
  ;;                (qbootctl-package qbootctl)))  ; in (fxtec-pro1x packages misc)
  ;;    (pro1x-audio-service-type
  ;;     config => (pro1x-audio-configuration
  ;;                (inherit config)
  ;;                UCM profiles and the voice call helper.
  ;;                (audio-package pro1x-audio)))  ; in (fxtec-pro1x packages audio)
  ;;    (pro1x-keyboard-service-type
  ;;     config => (pro1x-keyboard-configuration
  ;;                (inherit config)
  ;;                (xkb-layout \"us\")            ; session keyboard layout
  ;;                (xkb-variant \"intl\")
  ;;                (backlight-timeout 60)))     ; seconds, #f: never
  ;;    (pro1x-usb-network-service-type
  ;;     config => (pro1x-usb-network-configuration
  ;;                (inherit config)
  ;;                (address \"172.16.42.1\")      ; the phone over USB
  ;;                (prefix 24)))
  ;;    (pro1x-modem-service-type
  ;;     config => (pro1x-modem-configuration (inherit config) (verbose? #f)))
  ;;    (pro1x-sensors-service-type
  ;;     config => (pro1x-sensors-configuration
  ;;                (inherit config)
  ;;                (autostart? #t)
  ;;                (accel-mount-matrix \"-1, 0, 0; 0, -1, 0; 0, 0, 1\")
  ;;                (disable-recovery? #t)       ; no ADSP restart loop after a crash
  ;;                ;; Platform properties the ADSP asks for by name.
  ;;                (properties '((\"hw_platform\" . \"QRD\")))
  ;;                ;; Only to replace them: the sensor configuration tree, a directory
  ;;                ;; (default device/hexagonfs in the channel), and the daemon's package.
  ;;                ;; (hexagonfs (local-file \"hexagonfs\" #:recursive? #t))
  ;;                ;; (hexagonrpcd-package hexagonrpcd)   ; in (fxtec-pro1x packages misc)
  ;;                ))
  )
"))

(define (pro1x-user-config-service module procedure)
  "Return a service installing /etc/guix/config.scm for PROCEDURE in MODULE, and
/etc/guix/channels.scm.

Not through etc-service-type: an /etc entry under guix/ would turn the whole
of /etc/guix into a read-only store link and hide the acl and signing keys
Guix writes there.  Like guix-service-type for its channels.scm, link each
file in place at activation."
  (define files
    `(("config.scm" ,(plain-file "config.scm"
                                 (pro1x-user-config module procedure)))
      ("channels.scm" ,pro1x-channels-file)))

  (simple-service
   'pro1x-guix-files activation-service-type
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils))
         (mkdir-p "/etc/guix")
         (for-each
          (lambda (name file)
            (let ((target (string-append "/etc/guix/" name)))
              ;; A link into the store is ours from an earlier generation;
              ;; anything else was written by hand: keep it as .bak.
              (when (false-if-exception (lstat target))
                (if (and (symbolic-link? target)
                         (store-file-name? (readlink target)))
                    (delete-file target)
                    (rename-file target (string-append target ".bak"))))
              (symlink file target)))
          '#$(map car files)
          (list #$@(map cadr files)))))))

(define pro1x-reload-bus-service
  ;; After a deploy or reconfigure, the running system bus keeps its old
  ;; policy and polkitd its old actions and rules (it watched the previous
  ;; /etc/polkit-1), so new D-Bus services and polkit actions only worked
  ;; after a reboot: UPower exited with "name lost", polkit said "Action
  ;; ... is not registered" (2026-10-30).  At activation, when the bus is
  ;; running, reload its configuration and stop polkitd, which the bus
  ;; starts again on the next request.  At boot the bus is not up yet and
  ;; this does nothing.
  (simple-service
   'pro1x-reload-bus activation-service-type
   #~(when (file-exists? "/run/dbus/system_bus_socket")
       (system* #$(file-append dbus "/bin/dbus-send") "--system"
                "--type=method_call" "--dest=org.freedesktop.DBus"
                "/" "org.freedesktop.DBus.ReloadConfig")
       (system* #$(file-append procps "/bin/pkill") "-x" "polkitd"))))
