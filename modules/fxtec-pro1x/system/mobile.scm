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
             (gnu packages linux)
             (gnu packages networking)
             (gnu packages ntp)
             (gnu packages ssh)
             (gnu packages freedesktop)    ; libqmi, libqrtr-glib
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

;; What phoc starts: gsd-media-keys, then the shell.  Phosh does not
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
               "-S" "-C" "/etc/phoc.ini" "-E"
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
     "console=ttyMSM0,115200n8"
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
       ,(file-append pro1x-sway-config "/share/pro1x-sway/i3status-rust.toml")))
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

     ;; /etc/phoc.ini — scale ×2 for 1080×2160 panel
     (simple-service 'phosh-config etc-service-type
       (list
        `("phoc.ini"
          ,(plain-file "phoc.ini"
                       "[core]\n[output:DSI-1]\nscale=2\n"))))

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

     ;; D-Bus (required by Phosh, ModemManager, iio-sensor-proxy, …)
     (service dbus-root-service-type)
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
     foot sway wdisplays swayidle mako
     sway-launcher-desktop pro1x-sway-config fzf jq
     i3status-rust font-awesome
     grim slurp wl-clipboard brightnessctl playerctl
     ;; Browser, terminal, editors
     icecat gnome-console
     emacs mpv nnn
     calls chatty
     ;; Camera viewer: libcamera's cameras reach it through PipeWire
     ;; (WirePlumber's libcamera monitor); cameractrl only sets controls.
     snapshot
     libqmi libqrtr-glib
     iw ntp usbutils vim git font-terminus
     gsettings-desktop-schemas
     ;; Phosh requires these schemas at runtime: gnome-settings-daemon for
     ;; org.gnome.settings-daemon.plugins.power (phosh-pro1x compiles them in).
     gnome-settings-daemon)
    %base-packages))))
