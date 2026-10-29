;;; systems/mobile.scm — Pro1X Guix mobile desktop system
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

(define-module (systems mobile))

(use-modules (gnu)
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
               #$(file-append phoc-pro1x "/bin/phoc")
               "-S" "-C" "/etc/phoc.ini" "-E"
               ;; phosh 0.56 installs the shell in libexec; bin/phosh-session
               ;; wants gnome-session.
               #$(file-append phosh-pro1x "/libexec/phosh")))))

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
               #$(file-append sway "/bin/sway")))))

;; Root SSH key for scripts/deploy.sh.  keys/pro1x-guix.pub is not in git:
;; each owner puts their own public key there (README, "Updating without
;; reflashing").  Without it, root has no SSH login.
(define %root-ssh-keys
  (let ((file (string-append (dirname (or (current-filename) "systems/."))
                             "/../keys/pro1x-guix.pub")))
    (if (file-exists? file)
        `(("root" ,(local-file (canonicalize-path file) "pro1x-guix.pub")))
        '())))

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
     ;; phosh.desktop and swmo.desktop installed to /etc/wayland-sessions so
     ;; tuigreet can find them.  Both use absolute store paths in Exec= so they
     ;; work regardless of login-shell PATH.
     (simple-service 'wayland-sessions etc-service-type
       (list
        `("wayland-sessions/phosh.desktop"
          ,(mixed-text-file "phosh.desktop"
             "[Desktop Entry]\nName=Phosh\nExec="
             phosh-pro1x-session
             "\nType=Application\n"))
        `("wayland-sessions/swmo.desktop"
          ,(mixed-text-file "swmo.desktop"
             "[Desktop Entry]\nName=Sxmo + Sway\nExec="
             (file-append sxmo-utils "/bin/sxmo_swayinit.sh")
             "\nType=Application\n"))
        `("wayland-sessions/sway.desktop"
          ,(mixed-text-file "sway.desktop"
             "[Desktop Entry]\nName=Sway\nExec="
             sway-session
             "\nType=Application\n"))))

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
              (documentation "Load a 16x32 console font on tty1.")
              (start #~(lambda _
                         (system* #$(file-append kbd "/bin/setfont")
                                  "-C" "/dev/tty1"
                                  #$(file-append
                                     kbd "/share/consolefonts/"
                                     "latarcyrheb-sun32.psfu.gz"))
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
                               "--remember"
                               "--remember-user-session"
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
               (authorized-keys %root-ssh-keys))))

    ;; Base services — delete mingetty/login/console-font (greetd owns VT1;
    ;; console-font depends on term-ttyN provided by mingetty so must go too).
    (modify-services %base-services
      ;; /etc/guix/channels.scm: guix, nonguix, fxtec-pro1x.
      (guix-service-type config =>
        (guix-configuration
          (inherit config)
          (channels %pro1x-channels)))
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
     libqmi libqrtr-glib
     iw ntp usbutils vim git font-terminus
     gsettings-desktop-schemas
     ;; Phosh requires these schemas at runtime: gnome-settings-daemon for
     ;; org.gnome.settings-daemon.plugins.power (phosh-pro1x compiles them in).
     gnome-settings-daemon)
    %base-packages)))
