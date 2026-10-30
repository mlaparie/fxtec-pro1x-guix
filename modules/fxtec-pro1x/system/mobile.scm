;;; fxtec-pro1x/system/mobile.scm — the Pro¹x mobile system (Phosh, Sway, Sxmo)
;;;
;;; pro1x-mobile-operating-system returns the operating system the port
;;; ships; systems/mobile.scm and the users' own configurations build on it
;;; (operating-system (inherit (pro1x-mobile-operating-system …)) …), so
;;; guix pull brings the port's changes to customised systems too.
;;;
;;; ROOT-SSH-KEYS: public key files root may log in with, for guix deploy
;;; (scripts/deploy.sh); empty: no root SSH login.  See
;;; (fxtec-pro1x system common) for the key and /etc/guix/config.scm.
;;;
;;; Session selection: greetd + tuigreet on VT1
;;;   • Phosh   — phoc-pro1x compositor + phosh-pro1x shell
;;;   • Sxmo    — sway/Wayland via sxmo_swayinit.sh (sxmo-utils)
;;;   • Sway    — bare sway + foot (manual fallback; see README)
;;;
;;; Includes:
;;;   • Camera stack (libcamera-pro1x, cameractrl)
;;;   • ADSP sensors (accelerometer for auto-rotate, proximity, ALS)
;;;   • IceCat browser, GNOME Console, foot terminal, sway

(define-module (fxtec-pro1x system mobile)
  #:export (pro1x-mobile-operating-system))

(use-modules (gnu)
             (fxtec-pro1x system common)
             (guix gexp)
             (fxtec-pro1x packages bootloader)
             (gnu packages bash)
             (gnu packages fonts)
             (ice-9 match)
             (gnu packages admin)
             (gnu packages glib)
             (gnu packages base)
             (gnu packages gnome)
             (gnu packages libcanberra)    ; sound-theme-freedesktop
             (gnu packages librewolf)
             (gnu packages linux)
             (gnu packages networking)
             (gnu packages ntp)
             (gnu packages ssh)
             (gnu packages freedesktop)    ; libqmi, libqrtr-glib
             (gnu packages gstreamer)      ; gst-plugins-bad
             (gnu packages telephony)      ; libcallaudio (callaudiod)
             (gnu packages version-control)
             (gnu packages vim)
             (gnu packages messaging)
             (gnu packages gnuzilla)
             (gnu packages terminals)
             (gnu packages image)          ; grim, slurp
             (gnu packages music)          ; playerctl
             (gnu packages rust-apps)      ; i3status-rust
             (gnu packages web)            ; jq
             (gnu packages xdisorg)        ; wl-clipboard
             (gnu packages web-browsers)
             (gnu packages emacs)
             (gnu packages video)
             (gnu packages window-management)
             (nongnu packages linux)
             (gnu services base)
             (gnu services dbus)
             (gnu services desktop)
             (gnu services xorg)            ; screen-locker-service-type
             (gnu services networking)
             (gnu services shepherd)
             (gnu services ssh)
             (gnu system accounts)
             (gnu system file-systems)
             (fxtec-pro1x packages firmware)
             (fxtec-pro1x packages kernel)
             (fxtec-pro1x packages misc)
             (fxtec-pro1x packages sxmo)
             (fxtec-pro1x services audio)
             (fxtec-pro1x services boot)
             (fxtec-pro1x services channels)
             (fxtec-pro1x services camera)
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x services modem)
             (fxtec-pro1x services sensors)
             (fxtec-pro1x services usb-network))

;; Keyboard slider in Phosh: landscape while the keyboard is out.  Phosh
;; does not know SW_KEYPAD_SLIDE (gpio-keys, /dev/input/pro1x-slider, group
;; input), so with auto-rotation it also rotated with the keyboard out
;; (author, 2026-10-30).  On slide-out: remember the user's orientation
;; lock, lock, and turn the panel to landscape (transform 270: with 90,
;; as in Sway's config, Phosh came out upside down, author 2026-10-30);
;; Phosh leaves the transform alone while locked.  The on-screen keyboard
;; is turned off too while the keyboard is out (author).  On slide-in:
;; restore both remembered settings, so auto-rotation and the on-screen
;; keyboard come back if they were on.
(define phosh-pro1x-slider
  (program-file "phosh-pro1x-slider"
    #~(begin
        (use-modules (ice-9 binary-ports)
                     (ice-9 match)
                     (ice-9 popen)
                     (ice-9 rdelim)
                     (rnrs bytevectors))

        (define slider "/dev/input/pro1x-slider")
        (define gsettings (string-append #$glib:bin "/bin/gsettings"))
        (define schema "org.gnome.settings-daemon.peripherals.touchscreen")
        (define osk-schema "org.gnome.desktop.a11y.applications")

        (define (slider-open?)
          ;; `evtest --query' exits with 10 when the switch is set.
          (= 10 (status:exit-val
                 (system* #$(file-append evtest "/bin/evtest") "--query"
                          slider "EV_SW" "SW_KEYPAD_SLIDE"))))

        (define (setting schema key)
          (let* ((port (open-pipe* OPEN_READ gsettings "get" schema key))
                 (value (read-line port)))
            (close-pipe port)
            (if (eof-object? value) "false" value)))

        (define (set-setting! schema key value)
          (system* gsettings "set" schema key value))

        ;; SAVED: (orientation-lock . screen-keyboard-enabled) before
        ;; slide-out.
        (define (slid-out! saved)
          (let ((saved (or saved
                           (cons (setting schema "orientation-lock")
                                 (setting osk-schema
                                          "screen-keyboard-enabled")))))
            (set-setting! schema "orientation-lock" "true")
            (set-setting! osk-schema "screen-keyboard-enabled" "false")
            (system* #$(file-append wlr-randr "/bin/wlr-randr")
                     "--output" "DSI-1" "--transform" "270")
            saved))

        ;; With the rotation lock on (the default, phosh-pro1x's schema
        ;; override), closing the keyboard goes back to portrait: the lock
        ;; would otherwise keep the keyboard landscape (author, 2026-10-30).
        (define (slid-in! saved)
          (match saved
            ((lock . osk)
             (set-setting! schema "orientation-lock" lock)
             (set-setting! osk-schema "screen-keyboard-enabled" osk))
            (#f #t))
          (when (string=? (setting schema "orientation-lock") "true")
            (system* #$(file-append wlr-randr "/bin/wlr-randr")
                     "--output" "DSI-1" "--transform" "normal"))
          #f)

        ;; Let the shell start before the first change.
        (sleep 3)
        (let ((port (open-input-file slider #:binary #t)))
          (setvbuf port 'none)
          ;; SAVED: the user's settings before slide-out, #f while slid in.
          (let loop ((saved (if (slider-open?) (slid-out! #f) #f)))
            ;; struct input_event on aarch64: 16-byte timeval, u16 type,
            ;; u16 code, s32 value.  EV_SW 5, SW_KEYPAD_SLIDE 10.
            (let ((event (get-bytevector-n port 24)))
              (if (and (bytevector? event)
                       (= 5 (bytevector-u16-native-ref event 16))
                       (= 10 (bytevector-u16-native-ref event 18)))
                  (loop (if (= 1 (bytevector-s32-native-ref event 20))
                            (slid-out! saved)
                            (slid-in! saved)))
                  (loop saved))))))))

;; What phoc starts: gsd-media-keys, gsd-rfkill, mmsd-tng, the on-screen
;; keyboard, the MMS reminder, the slider helper, the idle dimmer, then the
;; shell.  Phosh does not
;; handle the volume keys itself; in GNOME sessions gnome-session starts
;; gnome-settings-daemon's media-keys helper, which grabs them through
;; Phosh.  Without it the volume keys did nothing (tested on the phone,
;; 2026-10-29: they work with it).  Its logind and session-manager
;; warnings are harmless.
(define phosh-pro1x-shell
  (program-file "phosh-pro1x-shell"
    #~(begin
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append gnome-settings-daemon
                                "/libexec/gsd-media-keys")
                 "gsd-media-keys"))
        ;; gsd-rfkill: Phosh's Bluetooth tile and GNOME Settings' Bluetooth
        ;; panel get the radios' state from it (org.gnome.SettingsDaemon.
        ;; Rfkill); without it Bluetooth looked off and could not be used
        ;; from the UI although BlueZ worked (scan found devices).
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append gnome-settings-daemon "/libexec/gsd-rfkill")
                 "gsd-rfkill"))
        ;; mmsd-tng: MMS for Chatty (no D-Bus activation file of its own).
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append mmsd-tng "/bin/mmsdtng") "mmsdtng"))
        ;; On-screen keyboard (sm.puri.OSK0); gnome-session would start it
        ;; from sm.puri.OSK0.desktop.
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append stevia "/bin/phosh-osk-stevia")
                 "phosh-osk-stevia" "--allow-replacement"))
        ;; Reminds about waiting MMS; the "Fetch MMS" launcher fetches them.
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append pro1x-mms-fetch "/bin/pro1x-mms-fetch")
                 "pro1x-mms-fetch"))
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$phosh-pro1x-slider "phosh-pro1x-slider"))
        ;; Dim the panel when idle (/etc/pro1x/dim.conf, from config.scm);
        ;; Phosh only blanks (dimming is gnome-settings-daemon's power
        ;; plugin, which needs logind).  Phosh still blanks after its own
        ;; delay.
        (when (zero? (primitive-fork))
          (setsid)
          (execl #$(file-append pro1x-sway-config "/bin/pro1x-idle")
                 "pro1x-idle"))
        ;; phosh 0.56 installs the shell in libexec; bin/phosh-session
        ;; wants gnome-session.
        (execl #$(file-append phosh-pro1x "/libexec/phosh") "phosh"))))

;; Phosh session launch script for greetd.  Uses absolute store paths so it
;; works regardless of PATH at session startup.
(define phosh-pro1x-session
  (program-file "start-phosh-pro1x"
    #~(begin
        (setenv "WLR_BACKENDS" "drm,libinput")
        (setenv "MOZ_ENABLE_WAYLAND" "1")
        ;; Upstream's session file has DesktopNames=Phosh;GNOME; which
        ;; greetd does not turn into XDG_CURRENT_DESKTOP.  Without it GNOME
        ;; Settings (OnlyShowIn=GNOME) is hidden and does not start.
        (setenv "XDG_CURRENT_DESKTOP" "Phosh:GNOME")
        (let ((d (getenv "XDG_DATA_DIRS")))
          (setenv "XDG_DATA_DIRS"
                  (string-append "/run/current-system/profile/share"
                                 (if d (string-append ":" d) ""))))
        ;; greetd's pam_mount creates /run/user/UID; fall back just in case.
        (unless (getenv "XDG_RUNTIME_DIR")
          (setenv "XDG_RUNTIME_DIR"
                  (string-append "/run/user/" (number->string (getuid)))))
        ;; ~/Pictures, ~/Music, ... and ~/.config/user-dirs.dirs, where
        ;; missing: Snapshot could not save ("Could not find
        ;; XDG_PICTURES_DIR").  Desktop sessions run this at login.
        (system* #$(file-append xdg-user-dirs "/bin/xdg-user-dirs-update"))
        ;; Keep the session's output (greetd discards it): /tmp/phosh-UID.log.
        (let ((log (open-file (string-append "/tmp/phosh-"
                                             (number->string (getuid))
                                             ".log")
                              "w")))
          (dup2 (fileno log) 1)
          (dup2 (fileno log) 2))
        (execl #$(file-append dbus "/bin/dbus-run-session")
               "dbus-run-session" "--"
               ;; PipeWire, WirePlumber, pipewire-pulse for the session.
               #$pro1x-audio-session
               #$(file-append phoc-pro1x "/bin/phoc")
               "-S" "-C"
               ;; The user's phoc.ini if there is one (scale), else ours.
               (let ((own (string-append (getenv "HOME")
                                         "/.config/phoc/phoc.ini")))
                 (if (file-exists? own) own "/etc/phoc.ini"))
               "-E"
               #$phosh-pro1x-shell))))

;; Sxmo on sway, for greetd.  Logs to /tmp/sxmo-UID.log (greetd discards
;; session output).  Sxmo also needs superd, its user service manager, not
;; packaged yet: its start hook waits for `superctl status' (TODO.md).
;; Same session bus and audio as the Sway session (Sxmo would start
;; PipeWire through superd); the device settings come from
;; /etc/sway/config.d/pro1x.conf, which Sxmo's sway template includes.
(define sxmo-session
  (program-file "start-sxmo"
    #~(begin
        (setenv "WLR_BACKENDS" "drm,libinput")
        (let ((d (getenv "XDG_DATA_DIRS")))
          (setenv "XDG_DATA_DIRS"
                  (string-append "/run/current-system/profile/share"
                                 (if d (string-append ":" d) ""))))
        (unless (getenv "XDG_RUNTIME_DIR")
          (setenv "XDG_RUNTIME_DIR"
                  (string-append "/run/user/" (number->string (getuid)))))
        ;; ~/Pictures, ~/Music, ... and ~/.config/user-dirs.dirs, where
        ;; missing: Snapshot could not save ("Could not find
        ;; XDG_PICTURES_DIR").  Desktop sessions run this at login.
        (system* #$(file-append xdg-user-dirs "/bin/xdg-user-dirs-update"))
        (let ((log (open-file (string-append "/tmp/sxmo-"
                                             (number->string (getuid))
                                             ".log")
                              "w")))
          (dup2 (fileno log) 1)
          (dup2 (fileno log) 2))
        (execl #$(file-append dbus "/bin/dbus-run-session")
               "dbus-run-session" "--"
               #$pro1x-audio-session
               #$(file-append sxmo-utils "/bin/sxmo_swayinit.sh")))))

;; Bare sway session for greetd.
(define sway-session
  (program-file "start-sway"
    #~(begin
        (setenv "WLR_BACKENDS" "drm,libinput")
        (setenv "MOZ_ENABLE_WAYLAND" "1")
        (let ((d (getenv "XDG_DATA_DIRS")))
          (setenv "XDG_DATA_DIRS"
                  (string-append "/run/current-system/profile/share"
                                 (if d (string-append ":" d) ""))))
        (unless (getenv "XDG_RUNTIME_DIR")
          (setenv "XDG_RUNTIME_DIR"
                  (string-append "/run/user/" (number->string (getuid)))))
        ;; ~/Pictures, ~/Music, ... and ~/.config/user-dirs.dirs, where
        ;; missing: Snapshot could not save ("Could not find
        ;; XDG_PICTURES_DIR").  Desktop sessions run this at login.
        (system* #$(file-append xdg-user-dirs "/bin/xdg-user-dirs-update"))
        ;; Keep the session's output (greetd discards it): /tmp/sway-UID.log.
        (let ((log (open-file (string-append "/tmp/sway-"
                                             (number->string (getuid))
                                             ".log")
                              "w")))
          (dup2 (fileno log) 1)
          (dup2 (fileno log) 2))
        ;; A session bus for mako and other clients, as for Phosh.  The
        ;; config is ~/.config/sway/config (skeleton below).
        (execl #$(file-append dbus "/bin/dbus-run-session")
               "dbus-run-session" "--"
               ;; PipeWire, WirePlumber, pipewire-pulse for the session.
               #$pro1x-audio-session
               #$(file-append sway "/bin/sway")))))

(define* (pro1x-mobile-operating-system #:key (root-ssh-keys '()))
  "Return the Pro¹x mobile operating system; ROOT-SSH-KEYS are public key
files root may log in with."
(operating-system
  (host-name "pro1x")
  (timezone "UTC")
  (locale "en_US.utf8")

  ;; ── Kernel ────────────────────────────────────────────────────────────────
  (kernel linux-pro1x)
  (kernel-arguments
   (append
    (list
     ;; No console=ttyMSM0: this phone has no UART device (/dev/ttyMSM0 is
     ;; absent), and Guix's serial getty (term-console) on that console
     ;; failed and was respawned every 10 s (2026-10-30).
     "console=tty1"
     ;; Text console (tuigreet) in landscape, like sway (keyboard out).
     "fbcon=rotate:1"
     ;; 16x32 console font from the start (kernel CONFIG_FONT_TER16x32);
     ;; before, early boot used 8x16 until setfont ran.
     "fbcon=font:TER16x32"
     "loglevel=4"
     "g_cdc.host_addr=02:50:31:e8:00:01"
     "g_cdc.dev_addr=02:50:31:e8:00:02")
    %default-kernel-arguments))

  (initrd-modules
   '("goodix_ts" "hid-multitouch"))

  ;; ── Firmware ──────────────────────────────────────────────────────────────
  (firmware (list linux-firmware firmware-fxtec-qx1050))

  ;; ── Bootloader ────────────────────────────────────────────────────────────
  (bootloader
   (bootloader-configuration
    (bootloader pro1x-extlinux-bootloader)
    (targets '("/dev/disk/by-partlabel/userdata"))
    ;; "GNU Guix Boot Options" stays 10 s (it cannot be navigated with the
    ;; phone buttons; hold volume-down at power-on for the U-Boot menu).
    (timeout 10)))

  ;; ── Filesystems ───────────────────────────────────────────────────────────
  (file-systems
   (cons*
    (file-system
      (device (file-system-label "guix"))
      (mount-point "/")
      (type "ext4")
      (flags '(no-atime)))
    %base-file-systems))

  ;; ── Home skeleton: sway and bar configs for new accounts ─────────────────
  (skeletons
   (append
    `((".config/sway/config"
       ,(file-append pro1x-sway-config "/share/pro1x-sway/config"))
      (".config/i3status-rust/config.toml"
       ,(file-append pro1x-sway-config "/share/pro1x-sway/i3status-rust.toml"))
      (".config/foot/foot.ini"
       ,(file-append pro1x-sway-config "/share/pro1x-sway/foot.ini"))
      ;; XDG user directories, set when the account is created (first boot
      ;; after flashing), as xdg-user-dirs-update would write them: Snapshot
      ;; saves into XDG_PICTURES_DIR and failed without it (2026-10-30).
      (".config/user-dirs.dirs"
       ,(plain-file "user-dirs.dirs"
                    (string-append
                     "XDG_DESKTOP_DIR=\"$HOME/Desktop\"\n"
                     "XDG_DOCUMENTS_DIR=\"$HOME/Documents\"\n"
                     "XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"\n"
                     "XDG_MUSIC_DIR=\"$HOME/Music\"\n"
                     "XDG_PICTURES_DIR=\"$HOME/Pictures\"\n"
                     "XDG_PUBLICSHARE_DIR=\"$HOME/Public\"\n"
                     "XDG_TEMPLATES_DIR=\"$HOME/Templates\"\n"
                     "XDG_VIDEOS_DIR=\"$HOME/Videos\"\n"))))
    (pro1x-root-key-skeletons root-ssh-keys)
    (default-skeletons)))

  ;; ── User accounts ─────────────────────────────────────────────────────────
  (users
   (cons*
    (user-account
     (name "user")
     (group "users")
     (home-directory "/home/user")
     (supplementary-groups
      '("wheel" "netdev" "video" "input" "audio" "feedbackd" "seat"))
     ;; Change this before relying on it.
     (password (crypt "123456" "$6$abc")))
    %base-user-accounts))

  ;; feedbackd group is added by pro1x-hardware-service-type via account-service-type

  ;; Guix's default sudoers, plus tuigreet's power menu (F12): the greeter
  ;; runs as "greeter", and halt/reboot need root (Shepherd's socket).
  (sudoers-file
   (plain-file "sudoers"
               (string-append (plain-file-content %sudoers-specification)
                              "greeter ALL=(root) NOPASSWD: "
                              "/run/current-system/profile/sbin/halt, "
                              "/run/current-system/profile/sbin/reboot\n")))

  ;; ── Services ──────────────────────────────────────────────────────────────
  (services
   (append
    (list
     ;; ── Hardware
     (service pro1x-hardware-service-type)
     ;; Backlight writable by the video group (brightnessctl's rules).
     (udev-rules-service 'brightnessctl brightnessctl)

     (service pro1x-usb-network-service-type)
     (service pro1x-keyboard-service-type
              (pro1x-keyboard-configuration
               (xkb-layout "us")
               (xkb-variant "intl")))
     (service pro1x-modem-service-type)
     (service pro1x-audio-service-type)
     (service pro1x-camera-service-type)
     (service pro1x-sensors-service-type)
     (service pro1x-rootfs-resize-service-type)
     (service pro1x-boot-success-service-type)
     (service pro1x-boot-menu-service-type
              (pro1x-boot-menu-configuration (generations 3)))

     ;; seatd: minimal seat manager; libseat uses its socket to open a DRM
     ;; session without needing a PAM login.  Provides the 'elogind symbol so
     ;; services that require elogind also wait for seatd.
     (service seatd-service-type)

     ;; UPower: Phosh's battery indicator and GNOME Settings read the battery
     ;; through it; without it Phosh showed a wrong battery state (sway's
     ;; i3status-rust reads sysfs and was right).
     (service upower-service-type)

     ;; ── Session desktop files ─────────────────────────────────────────────
     ;; Session entries in /etc/wayland-sessions for tuigreet, with absolute
     ;; store paths in Exec= so they work regardless of login-shell PATH.
     ;; tuigreet sorts them by Name; the numbers give the order Sway, Phosh,
     ;; Sxmo (the author's choice, Sway first).
     (simple-service 'wayland-sessions etc-service-type
       (list
        `("wayland-sessions/phosh.desktop"
          ,(mixed-text-file "phosh.desktop"
             "[Desktop Entry]\nName=2 Phosh\nExec="
             phosh-pro1x-session
             "\nType=Application\n"))
        `("wayland-sessions/swmo.desktop"
          ,(mixed-text-file "swmo.desktop"
             "[Desktop Entry]\nName=3 Sxmo + Sway\nExec="
             sxmo-session
             "\nType=Application\n"))
        `("wayland-sessions/sway.desktop"
          ,(mixed-text-file "sway.desktop"
             "[Desktop Entry]\nName=1 Sway\nExec="
             sway-session
             "\nType=Application\n"))))

     ;; Device settings shared by the Sway and Sxmo sessions.
     (simple-service 'sway-device-config etc-service-type
       (list
        `("sway/config.d/pro1x.conf"
          ,(file-append pro1x-sway-config "/share/pro1x-sway/pro1x.conf"))))

     ;; /etc/phoc.ini — scale 1.75 for the 1080×2160 panel (author's
     ;; default, 2026-10-30; was 2).  Phosh does not save display changes,
     ;; so a scale set in Settings lasts until logout; to keep one, copy
     ;; this file to ~/.config/phoc/phoc.ini and edit it there.
     (simple-service 'phosh-config etc-service-type
       (list
        `("phoc.ini"
          ,(plain-file "phoc.ini"
                       "[core]\n[output:DSI-1]\nscale=1.75\n"))))

     ;; /etc/pam.d/phosh: the lock screen checks the passcode with PAM
     ;; service "phosh"; without it PAM falls back to "other" and denies.
     (simple-service 'phosh-pam pam-root-service-type
       (list (unix-pam-service "phosh")))

     ;; Console font for tuigreet: 16x32, double the kernel's 8x16.  Guix's
     ;; console-font-service-type needs mingetty's term-ttyN, removed here.
     (simple-service 'pro1x-console-font shepherd-root-service-type
       (list (shepherd-service
              (provision '(pro1x-console-font))
              (requirement '(virtual-terminal))
              (one-shot? #t)
              (documentation "Console for tuigreet: 16x32 font on tty1,
Dracula palette, no kernel messages over the greeter.")
              (start #~(lambda _
                         (system* #$(file-append kbd "/bin/setfont")
                                  "-C" "/dev/tty1"
                                  #$(file-append
                                     kbd "/share/consolefonts/"
                                     "latarcyrheb-sun32.psfu.gz"))
                         ;; Dracula (draculatheme.com) as the 16 console
                         ;; colours, red/green/blue rows; colour 0 is the
                         ;; background #282a36.  Not vt.default_* on the
                         ;; kernel command line: U-Boot refuses command
                         ;; lines over 511 bytes (CONFIG_SYS_CBSIZE=512).
                         (system* #$(file-append kbd "/bin/setvtrgb")
                                  #$(plain-file "dracula.vtrgb" "\
40,255,80,241,189,255,139,248,98,255,105,255,214,255,164,255
42,85,250,250,147,121,233,248,114,110,255,255,172,146,255,255
54,85,123,140,249,198,253,242,164,110,148,165,255,223,255,255
"))
                         ;; Late driver errors and warnings went over
                         ;; tuigreet; they stay in dmesg.
                         (system* #$(file-append util-linux "/bin/dmesg")
                                  "-n" "1")
                         #t)))))

     ;; ── greetd + tuigreet session picker ─────────────────────────────────
     ;; Replaces the direct phosh shepherd service.  tuigreet shows a session
     ;; menu on VT1; sessions are in /etc/wayland-sessions (above).
     ;; --session-wrapper "bash -lc" sources the login profile so PATH and
     ;; XDG_DATA_DIRS are populated before the session script runs.
     (service greetd-service-type
              (greetd-configuration
               (terminals
                (list
                 (greetd-terminal-configuration
                  (terminal-vt "1")
                  (terminal-switch #t)
                  (extra-shepherd-requirement
                   '(udev dbus-system seatd pro1x-console-font))
                  (default-session-command
                    (program-file "tuigreet-session"
                      #~(execl #$(file-append tuigreet "/bin/tuigreet")
                               "tuigreet"
                               "--time"
                               "--asterisks"
                               ;; Running kernel, read when tuigreet starts.
                               "--greeting"
                               (string-append "GNU Guix System on the F(x)tec Pro¹x"
                                              " · Linux "
                                              (utsname:release (uname))
                                              " (tty1)")
                               ;; Named colours map to the Dracula console
                               ;; palette set by pro1x-console-font.
                               "--theme"
                               (string-append
                                "border=magenta;text=cyan;prompt=green;"
                                "time=red;action=blue;button=yellow;"
                                "container=black;input=red")
                               "--remember"
                               "--remember-user-session"
                               ;; F12 power menu; sudoers allows exactly these.
                               "--power-shutdown"
                               "/run/privileged/bin/sudo /run/current-system/profile/sbin/halt"
                               "--power-reboot"
                               "/run/privileged/bin/sudo /run/current-system/profile/sbin/reboot"
                               "--sessions" "/etc/wayland-sessions"
                               ;; No logind here: without LIBSEAT_BACKEND
                               ;; libseat fails ("Unable to create seat:
                               ;; Function not implemented") and every
                               ;; session exits at once.
                               "--session-wrapper"
                               (string-append
                                #$(file-append coreutils "/bin/env")
                                " LIBSEAT_BACKEND=seatd "
                                #$(file-append bash "/bin/bash") " -lc")))))))))

     ;; swaylock's PAM service: without it swaylock cannot unlock, so Sway
     ;; had no idle lock (pro1x-idle --sway locks after lock-after).
     (service screen-locker-service-type
              (screen-locker-configuration
               (name "swaylock")
               (program (file-append swaylock "/bin/swaylock"))
               (using-pam? #t)
               (using-setuid? #f)))

     ;; tuigreet's --remember and --remember-user-session write the last
     ;; user and each user's last session in /var/cache/tuigreet, which did
     ;; not exist (no /var/cache at all), so nothing was remembered.
     (simple-service 'tuigreet-cache activation-service-type
       (with-imported-modules '((guix build utils))
         #~(begin
             (use-modules (guix build utils))
             (let ((dir "/var/cache/tuigreet")
                   (greeter (false-if-exception (getpwnam "greeter"))))
               (mkdir-p dir)
               (when greeter
                 (chown dir (passwd:uid greeter) (passwd:gid greeter)))))))

     ;; D-Bus (required by Phosh, ModemManager, iio-sensor-proxy etc.)
     (service dbus-root-service-type)
     ;; GTK 3 finds its input-method modules (the Wayland one talks to the
     ;; on-screen keyboard) only through this variable: GTK has no cache of
     ;; its own here and gtk+ is not in the profile itself, so its search
     ;; path is never set.  Without it no GTK 3 text field asked for stevia
     ;; in Phosh (2026-10-30).
     (simple-service 'gtk3-im-modules session-environment-service-type
                     '(("GUIX_GTK3_IM_MODULE_FILE"
                        . "/run/current-system/profile/lib/gtk-3.0/3.0.0/immodules-gtk3.cache")))
     ;; BlueZ.  The WCN3950 works when powered from boot; on Linux 7.1 it
     ;; does not answer again after a power-down (reported on SailfishOS,
     ;; gone on 7.3), so it is powered at start and toggling it off in the
     ;; shell can need a reboot to bring it back.
     (service bluetooth-service-type
              (bluetooth-configuration
               (auto-enable? #t)))

     ;; NetworkManager + wpa_supplicant (NM requires wireless-daemon)
     (service network-manager-service-type
              (network-manager-configuration
               ;; In conf.d, not through etc-service-type: an /etc entry
               ;; makes /etc/NetworkManager a read-only store link, and NM's
               ;; activation then fails to create system-connections.
               (extra-configuration-files
                (list
                 ;; Leave usb0 to pro1x-usb-network (static IP, dnsmasq).
                 `("unmanaged.conf"
                   ,(plain-file "nm-unmanaged.conf"
                                "[keyfile]\nunmanaged-devices=interface-name:usb0\n"))
                 ;; Saved connections stay where earlier images put them.
                 `("connections.conf"
                   ,(plain-file "nm-connections.conf"
                                "[keyfile]\npath=/var/lib/NetworkManager/system-connections\n"))))))
     (service wpa-supplicant-service-type)

     ;; NTP — no hardware RTC; -g allows stepping the clock from 1970
     (service ntp-service-type
              (ntp-configuration
               (allow-large-adjustment? #t)))

     ;; SSH
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #t)
               ;; Root by key only, for guix deploy (scripts/deploy.sh).
               (permit-root-login 'prohibit-password)
               (authorized-keys (pro1x-root-authorized-keys root-ssh-keys))))

     ;; /etc/guix/config.scm: the owner's starting configuration.
     pro1x-reload-bus-service
     (pro1x-user-config-service '(fxtec-pro1x system mobile)
                                'pro1x-mobile-operating-system))

    ;; Base services — delete mingetty/login/console-font (greetd owns VT1;
    ;; console-font depends on term-ttyN provided by mingetty so must go too).
    (modify-services %base-services
      (delete login-service-type)
      (delete mingetty-service-type)
      (delete console-font-service-type))))

  ;; ── System packages ───────────────────────────────────────────────────────
  (packages
   (append
    (list
     ;; Mobile UIs
     phoc-pro1x
     phosh-pro1x
     ;; Phosh Mobile Settings opens from the gear in Phosh's top panel,
     ;; GNOME Settings from a long press on a quick setting.
     phosh-mobile-settings
     gnome-control-center
     sxmo-utils
     clickclack
     ;; Sway session (config: device/sway, Super = yellow arrows)
     foot sway wdisplays swayidle swaylock mako
     sway-launcher-desktop pro1x-sway-config fzf jq
     ;; On-screen keyboard in Sway (Phosh starts it by store path).
     stevia
     ;; Event sounds for feedbackd (ringtone, messages): only alsa and gnome
     ;; sounds were installed, no theme with the freedesktop names.
     sound-theme-freedesktop
     ;; Sway and Phosh backgrounds (light and dark).
     pro1x-wallpapers
     i3status-rust font-awesome
     grim slurp wl-clipboard brightnessctl playerctl
     ;; Browser, terminal, editors
     ;; Epiphany (GNOME Web): adaptive, fits the phone in Phosh; IceCat kept.
     icecat epiphany gnome-console
     ;; LibreWolf: Firefox 158 with privacy defaults; aarch64 substitutes on
     ;; bordeaux (nonguix's firefox is x86_64 only).
     librewolf
     emacs mpv nnn
     calls chatty
     ;; callaudiod: Calls switches speaker and earpiece and mutes the
     ;; microphone through it (org.mobian_project.CallAudio).  It was only a
     ;; library dependency of Calls, so its D-Bus service was not found and
     ;; the speaker and mute buttons did nothing (author, 2026-10-30).
     libcallaudio
     ;; Fetch MMS launcher (the session starts the reminder).
     pro1x-mms-fetch
     ;; Camera viewer: libcamera's cameras reach it through PipeWire
     ;; (WirePlumber's libcamera monitor); cameractrl only sets controls.
     ;; It saves photos with jifmux (gst-plugins-bad) into XDG_PICTURES_DIR
     ;; (~/.config/user-dirs.dirs, skeleton below): without either, "Could
     ;; not take picture" (2026-10-30).
     snapshot gst-plugins-bad xdg-user-dirs
     ;; Portals: libadwaita apps read dark/light from the Settings portal
     ;; (gtk backend per Phosh's portals.conf); without them GNOME
     ;; Settings' dark mode changed nothing (2026-10-30).
     xdg-desktop-portal xdg-desktop-portal-gtk
     ;; feedbackd: vibration and event feedback for Phosh, Calls, Chatty.
     ;; It was only a dependency, not in the profile, so its D-Bus session
     ;; service was not found and nothing vibrated.  fbcli to test.
     ;; feedbackd-0.8: the version Phosh and Calls are built with here.
     feedbackd-0.8
     ;; bluetoothctl, btmgmt: the BlueZ tools were missing, so Bluetooth
     ;; could not be tested from a shell (the daemon came from the service).
     bluez
     libqmi libqrtr-glib
     iw ntp usbutils vim git font-terminus
     gsettings-desktop-schemas pro1x-gsettings-defaults
     ;; Phosh requires these schemas at runtime: gnome-settings-daemon for
     ;; org.gnome.settings-daemon.plugins.power (phosh-pro1x compiles them in).
     gnome-settings-daemon)
    %base-packages))))
