;;; systems/phosh.scm — Pro1X Guix system with Phosh mobile desktop
;;;
;;; Extends minimal.scm with:
;;;   • Phosh (phoc-pro1x compositor + squeekboard on-screen keyboard)
;;;   • Camera stack (libcamera-pro1x, cameractrl)
;;;   • ADSP sensors (accelerometer for auto-rotate, proximity, ALS)
;;;   • Calls (dialer), Chatty (SMS/MMS), Firefox, GNOME Console

(use-modules (gnu)
             (gnu bootloader extlinux)
             (gnu packages admin)
             (gnu packages base)
             (gnu packages gnome)
             (gnu packages linux)
             (gnu packages networking)
             (gnu packages ssh)
             (gnu packages version-control)
             (gnu packages vim)
             (gnu packages web-browsers)
             (nongnu packages linux)
             (nongnu packages mozilla)
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
             (fxtec-pro1x services audio)
             (fxtec-pro1x services boot)
             (fxtec-pro1x services camera)
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x services modem)
             (fxtec-pro1x services sensors)
             (fxtec-pro1x services usb-network))

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
     "loglevel=4"
     "g_cdc.host_addr=02:50:31:e8:00:01"
     "g_cdc.dev_addr=02:50:31:e8:00:02")
    %default-kernel-arguments))

  (initrd-modules
   (append '("goodix_ts") (base-initrd-modules linux-pro1x)))

  ;; ── Firmware ──────────────────────────────────────────────────────────────
  (firmware (list linux-firmware firmware-fxtec-qx1050))

  ;; ── Bootloader ────────────────────────────────────────────────────────────
  (bootloader
   (bootloader-configuration
    (bootloader extlinux-bootloader)
    (targets '("/dev/disk/by-partlabel/userdata"))
    (timeout 3)))

  ;; ── Filesystems ───────────────────────────────────────────────────────────
  (file-systems
   (cons*
    (file-system
      (device (file-system-label "guix"))
      (mount-point "/")
      (type "ext4")
      (options "noatime"))
    %base-file-systems))

  ;; ── User accounts ─────────────────────────────────────────────────────────
  (users
   (cons*
    (user-account
     (name "user")
     (group "users")
     (home-directory "/home/user")
     (supplementary-groups
      '("wheel" "netdev" "video" "input" "audio" "feedbackd")))
    %base-user-accounts))

  ;; feedbackd group is added by pro1x-hardware-service-type via account-service-type

  ;; ── Services ──────────────────────────────────────────────────────────────
  (services
   (append
    (list
     ;; ── Hardware
     (service pro1x-hardware-service-type)
     (service pro1x-usb-network-service-type)
     (service pro1x-keyboard-service-type
              (pro1x-keyboard-configuration
               (xkb-layout "fi")
               (xkb-variant "nodeadkeys")))
     (service pro1x-modem-service-type)
     (service pro1x-audio-service-type)
     (service pro1x-camera-service-type)
     (service pro1x-sensors-service-type)
     (service pro1x-boot-success-service-type)
     (service pro1x-boot-menu-service-type
              (pro1x-boot-menu-configuration (generations 3)))

     ;; ── Phosh desktop
     ;; phoc-pro1x ignores SW_KEYPAD_SLIDE so the keyboard slider
     ;; doesn't crash-loop the compositor.  Auto-started as 'user' on
     ;; VT1; XDG_RUNTIME_DIR is set up inline (no elogind needed).
     (simple-service 'phosh shepherd-root-service-type
       (list
        (shepherd-service
         (provision '(phosh))
         (requirement '(user-processes udev dbus-system file-systems))
         (documentation "Phosh mobile shell (phoc + squeekboard)")
         (start
          #~(make-forkexec-constructor
             (list #$(file-append shadow "/bin/su") "-l" "user"
                   "-s" "/bin/sh" "-c"
                   (string-append
                    "mkdir -p /run/user/1000 && chmod 0700 /run/user/1000 && "
                    "exec env XDG_RUNTIME_DIR=/run/user/1000 "
                    #$(file-append phoc-pro1x "/bin/phoc")
                    " -C /etc/phoc.ini -E squeekboard"))
             #:log-file "/var/log/phosh.log"))
         (stop #~(make-kill-destructor))
         (respawn? #t))))

     ;; /etc/phoc.ini — scale ×2 for 1080×2160 panel
     (simple-service 'phosh-config etc-service-type
       (list
        `("phoc.ini"
          ,(plain-file "phoc.ini"
                       "[core]\n[output:DSI-1]\nscale=2\n"))))

     ;; D-Bus (required by Phosh, ModemManager, iio-sensor-proxy, …)
     (service dbus-root-service-type)

     ;; NetworkManager + wpa_supplicant (NM requires wireless-daemon)
     (service network-manager-service-type)
     (service wpa-supplicant-service-type)

     ;; SSH
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #t))))

    ;; Base services (console-font, udev, syslog, etc.)
    %base-services))

  ;; ── System packages ───────────────────────────────────────────────────────
  (packages
   (append
    (list
     ;; Mobile apps
     firefox
     gnome-console
     ;; Calls (dialer) requires ModemManager + callaudiod — install here
     ;; and wire through dconf when available in Guix packages
     ;; chatty (SMS/MMS) — add once dependency on libolm is resolved
     iw usbutils vim git)
    %base-packages)))
