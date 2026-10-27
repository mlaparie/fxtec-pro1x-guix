;;; systems/mobile-encrypted.scm — Pro1X mobile system with LUKS2 full-disk encryption
;;;
;;; Partition layout of /dev/disk/by-partlabel/userdata:
;;;   [0,  256 MiB) : plain ext4 "guixboot" — U-Boot reads kernel + extlinux.conf from here
;;;   [256 MiB, …)  : LUKS2 container — passphrase entered in initrd, root mounted from here
;;;
;;; First flash:
;;;   bash scripts/flash-encrypted.sh systems/mobile-encrypted.scm
;;;
;;; After guix system reconfigure:
;;;   bash scripts/update-encrypted-boot.sh
;;;   (copies new kernel/initrd to the plain /boot area)

(define-module (systems mobile-encrypted))

(use-modules (gnu)
             (fxtec-pro1x packages bootloader)
             (gnu packages fonts)
             (ice-9 match)
             (gnu packages admin)
             (gnu packages base)
             (gnu packages gnome)
             (gnu packages linux)
             (gnu packages networking)
             (gnu packages ssh)
             (gnu packages version-control)
             (gnu packages emacs)
             (gnu packages video)
             (gnu packages vim)
             (gnu packages gnuzilla)
             (gnu packages web-browsers)
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
             (fxtec-pro1x services audio)
             (fxtec-pro1x services boot)
             (fxtec-pro1x services camera)
             (fxtec-pro1x services fde)
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x services modem)
             (fxtec-pro1x services sensors)
             (fxtec-pro1x services usb-network))

;; Defined here so both mapped-devices and file-systems can reference it.
(define %fde-mapped-devices
  (list
   (mapped-device
    (source "/dev/disk/by-partlabel/userdata")
    (targets '("pro1x-crypt"))
    (type luks-pro1x-device-mapping))))

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
   '("goodix_ts" "hid-multitouch"))

  ;; ── Firmware ──────────────────────────────────────────────────────────────
  (firmware (list linux-firmware firmware-fxtec-qx1050))

  ;; ── Bootloader ────────────────────────────────────────────────────────────
  ;; U-Boot reads extlinux.conf from the plain "guixboot" ext4 at the start of
  ;; userdata.  flash-encrypted.sh writes the kernel and initrd there at
  ;; /vmlinuz and /initrd.img with a matching extlinux.conf.
  ;; After guix system reconfigure, run scripts/update-encrypted-boot.sh to
  ;; copy the new kernel/initrd to the plain area.
  (bootloader
   (bootloader-configuration
    (bootloader pro1x-extlinux-bootloader)
    (targets '("/dev/disk/by-partlabel/userdata"))
    (timeout 3)))

  ;; ── Encrypted device + filesystems ────────────────────────────────────────
  (mapped-devices %fde-mapped-devices)

  (file-systems
   (cons*
    ;; Plain 256 MiB boot area — U-Boot reads kernel + extlinux.conf from here.
    (file-system
      (device (file-system-label "guixboot"))
      (mount-point "/boot")
      (type "ext4")
      (check? #f)
      (options "noatime"))
    ;; Encrypted root on the LUKS2 device.
    (file-system
      (device (file-system-label "guix"))
      (mount-point "/")
      (type "ext4")
      (options "noatime")
      (dependencies %fde-mapped-devices))
    %base-file-systems))

  ;; ── User accounts ─────────────────────────────────────────────────────────
  (users
   (cons*
    (user-account
     (name "user")
     (group "users")
     (home-directory "/home/user")
     (supplementary-groups
      '("wheel" "netdev" "video" "input" "audio" "feedbackd"))
     (password (crypt "123456" "$6$abc")))
    %base-user-accounts))

  ;; ── Services ──────────────────────────────────────────────────────────────
  (services
   (append
    (list
     (service pro1x-hardware-service-type)

     (simple-service 'nm-unmanaged-usb0 etc-service-type
       (list `("NetworkManager/conf.d/unmanaged.conf"
               ,(plain-file "nm-unmanaged.conf"
                            "[keyfile]\nunmanaged-devices=interface-name:usb0\n"))))
     (simple-service 'nm-connections-dir etc-service-type
       (list `("NetworkManager/conf.d/connections.conf"
               ,(plain-file "nm-connections.conf"
                            "[keyfile]\npath=/var/lib/NetworkManager/system-connections\n"))))
     (service pro1x-usb-network-service-type)
     (service pro1x-keyboard-service-type
              (pro1x-keyboard-configuration
               (xkb-layout "fi")
               (xkb-variant "nodeadkeys")))
     (service pro1x-modem-service-type)
     (service pro1x-audio-service-type)
     (service pro1x-camera-service-type)
     (service pro1x-sensors-service-type)
     (service pro1x-rootfs-resize-service-type)
     (service pro1x-boot-success-service-type)
     (service pro1x-boot-menu-service-type
              (pro1x-boot-menu-configuration (generations 3)))

     (simple-service 'phosh shepherd-root-service-type
       (list
        (shepherd-service
         (provision '(phosh))
         (requirement '(user-processes udev dbus-system file-systems))
         (documentation "Phosh mobile shell (phoc + squeekboard)")
         (start
          #~(make-forkexec-constructor
             (list "/bin/sh" "-c"
                   (string-append
                    "mkdir -p /run/user/1000"
                    " && chown 1000:1000 /run/user/1000"
                    " && chmod 0700 /run/user/1000"
                    " && exec " #$(file-append shadow "/bin/su")
                    " -l user -s /bin/sh -c"
                    " 'exec env XDG_RUNTIME_DIR=/run/user/1000 "
                    #$(file-append phoc-pro1x "/bin/phoc")
                    " -C /etc/phoc.ini -E squeekboard'"))
             #:log-file "/var/log/phosh.log"))
         (stop #~(make-kill-destructor))
         (respawn? #t))))

     (simple-service 'phosh-config etc-service-type
       (list
        `("phoc.ini"
          ,(plain-file "phoc.ini"
                       "[core]\n[output:DSI-1]\nscale=2\n"))))

     (service elogind-service-type)
     (service dbus-root-service-type)
     (service network-manager-service-type)
     (service wpa-supplicant-service-type)

     ;; NTP — no hardware RTC; -g allows stepping the clock from 1970
     (service ntp-service-type
              (ntp-configuration
               (allow-large-adjustment? #t)))

     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #t))))

    (modify-services %base-services
      (console-font-service-type config =>
        (map (match-lambda
               ((tty . _)
                (cons tty (file-append font-terminus
                                       "/share/consolefonts/ter-128n.psf.gz"))))
             config)))))

  ;; ── System packages ───────────────────────────────────────────────────────
  (packages
   (append
    (list
     icecat
     gnome-console
     iw usbutils vim git font-terminus
     gsettings-desktop-schemas
     phoc-pro1x
     emacs mpv nnn)
    %base-packages)))
