;;; fxtec-pro1x/system/minimal.scm — moved from systems/minimal.scm
;;;
;;; Build and deploy:
;;;   guix system image --system=aarch64-linux systems/minimal.scm
;;;
;;; Or on an aarch64 machine / via offloading:
;;;   guix system reconfigure systems/minimal.scm
;;;
;;; Flash (after building u-boot-pro1x separately):
;;;   See scripts/flash.sh

(define-module (fxtec-pro1x system minimal)
  #:export (pro1x-minimal-operating-system))


(use-modules (gnu)
             (fxtec-pro1x packages bootloader)
             (gnu packages fonts)
             (gnu services desktop)
             (ice-9 match)
             (gnu packages admin)
             (gnu packages base)
             (gnu packages linux)
             (gnu packages networking)
             (nongnu packages linux)
             (gnu packages ssh)
             (gnu packages version-control)
             (gnu packages vim)
             (gnu services dbus)
             (gnu services networking)
             (gnu services shepherd)
             (gnu services ssh)
             (gnu system accounts)
             (gnu system file-systems)
             (fxtec-pro1x packages firmware)
             (fxtec-pro1x packages kernel)
             (fxtec-pro1x services audio)
             (fxtec-pro1x services boot)
             (fxtec-pro1x services channels)
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x services modem)
             (fxtec-pro1x services usb-network))

(define* (pro1x-minimal-operating-system #:key (root-ssh-keys '()))
  "Return the Pro¹x minimal operating system, with ROOT-SSH-KEYS as root's
authorized SSH keys."
(operating-system
  (host-name "pro1x")
  (timezone "UTC")
  (locale "en_US.utf8")

  ;; ── Kernel ────────────────────────────────────────────────────────────────
  (kernel linux-pro1x)
  (kernel-arguments
   (append
    (list
     ;; UART console (debug) + framebuffer console, loglevel quiet
     "console=ttyMSM0,115200n8"
     "console=tty1"
     "loglevel=4"
     ;; USB CDC gadget with fixed MACs for stable PC interface name
     "g_cdc.host_addr=02:50:31:e8:00:01"
     "g_cdc.dev_addr=02:50:31:e8:00:02"
     ;; Nord palette in the framebuffer TTY
     "vt.default_red=0x3b,0xbf,0xa3,0xeb,0x81,0xb4,0x88,0xe5,0x4c,0xbf,0xa3,0xeb,0x81,0xb4,0x8f,0xec"
     "vt.default_grn=0x3b,0x61,0xbe,0xcb,0xa1,0x88,0xc0,0xe5,0x56,0x61,0xbe,0xcb,0xa1,0x88,0xbc,0xef"
     "vt.default_blu=0x3b,0x61,0x8c,0x8b,0xc1,0xe8,0xd3,0xe5,0x66,0x61,0x8c,0x8b,0xc1,0xe8,0xbb,0xf4")
    %default-kernel-arguments))

  ;; The Pro1X kernel selects the DTB at build time; extlinux passes it via
  ;; the FDT directive automatically when the DTB is next to the kernel.
  (initrd-modules
   ;; UFS storage and ext4 are built-in; base-initrd-modules pulls in
   ;; x86/generic modules (hid-apple, uas, serpent_generic…) absent from
   ;; this ARM kernel.  List only what actually exists.
   '("goodix_ts" "hid-multitouch"))

  ;; ── Firmware ──────────────────────────────────────────────────────────────
  ;; linux-firmware for Wi-Fi (ath10k), BT (qca); pro1x firmware for
  ;; GPU (a610), modem remoteproc images, sensors DSP.
  (firmware (list linux-firmware firmware-fxtec-qx1050))

  ;; ── Bootloader ────────────────────────────────────────────────────────────
  ;; U-Boot is flashed separately (scripts/flash.sh) and reads extlinux.conf
  ;; from the ext4 rootfs.  The target device is the userdata partition.
  (bootloader
   (bootloader-configuration
    (bootloader pro1x-extlinux-bootloader)
    ;; U-Boot looks for extlinux.conf via sysboot on the ext4 userdata partition.
    (targets '("/dev/disk/by-partlabel/userdata"))
    (menu-entries '())           ; extra entries managed by pro1x-boot-menu
    ;; "GNU Guix Boot Options" stays 10 s (it cannot be navigated with the
    ;; phone buttons; hold volume-down at power-on for the U-Boot menu).
    (timeout 10)))

  ;; ── Filesystems ───────────────────────────────────────────────────────────
  (file-systems
   (cons*
    ;; Root on the userdata partition (ext4, ~50 GB).
    ;; Label set by scripts/flash.sh.
    (file-system
      (device (file-system-label "guix"))
      (mount-point "/")
      (type "ext4")
      (flags '(no-atime)))
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
     ;; Change this before relying on it.
     (password (crypt "123456" "$6$abc")))
    %base-user-accounts))

  ;; feedbackd group is added by pro1x-hardware-service-type via account-service-type

  ;; ── Services ──────────────────────────────────────────────────────────────
  (services
   (append
    (list
     ;; Hardware baseline: udev rules, feedbackd group
     (service pro1x-hardware-service-type)

     ;; USB gadget Ethernet + DHCP server
     (service pro1x-usb-network-service-type)

     ;; Keyboard Fn-layer and layout
     (service pro1x-keyboard-service-type)

     ;; Modem: tqftpserv + rmtfs + ModemManager
     ;; (Wi-Fi firmware also goes through tqftpserv — keep enabled)
     (service pro1x-modem-service-type)

     ;; Audio: UCM2, WirePlumber S16LE fix, audio-init
     (service pro1x-audio-service-type)

     ;; Boot slot marking (Qualcomm A/B)
     (service pro1x-boot-success-service-type)

     ;; Previous-generation extlinux entries for the U-Boot menu
     ;; N must match previous-generations in u-boot-pro1x.
     (service pro1x-boot-menu-service-type
              (pro1x-boot-menu-configuration
               (generations 3)))

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
                                "[keyfile]\nunmanaged-devices=interface-name:usb0\n"))))))
     (service wpa-supplicant-service-type)

     ;; SSH for USB-ethernet access
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #t)
               ;; Root by key only, for guix deploy (scripts/deploy.sh).
               (permit-root-login 'prohibit-password)
               (authorized-keys root-ssh-keys)))

     ;; tuigreet on tty1; plain agreety on tty2-6
     (service greetd-service-type
              (greetd-configuration
               (terminals
                (list
                 (greetd-terminal-configuration
                  (terminal-vt "1")
                  (terminal-switch #t)
                  (default-session-command
                    (program-file "tuigreet-session"
                      #~(execl #$(file-append tuigreet "/bin/tuigreet")
                               "tuigreet"
                               "--greeting" "F(x)tec Pro1X — GNU Guix"
                               "--asterisks"
                               "--time"
                               "--cmd" "bash -l"
                               "--remember"
                               "--power-shutdown" "halt"
                               "--power-reboot" "reboot"))))
                 (greetd-terminal-configuration (terminal-vt "2"))
                 (greetd-terminal-configuration (terminal-vt "3"))
                 (greetd-terminal-configuration (terminal-vt "4"))
                 (greetd-terminal-configuration (terminal-vt "5"))
                 (greetd-terminal-configuration (terminal-vt "6")))))))

    ;; Base Guix services — large font, remove getty (greetd takes over)
    (modify-services %base-services
      ;; /etc/guix/channels.scm: guix, nonguix, fxtec-pro1x.
      (guix-service-type config =>
        (guix-configuration
          (inherit config)
          (channels %pro1x-channels)))
      (console-font-service-type config =>
        (map (match-lambda
               ((tty . _)
                (cons tty (file-append font-terminus
                                       "/share/consolefonts/ter-128n.psf.gz"))))
             config))
      (delete login-service-type)
      (delete mingetty-service-type))))

  ;; ── System packages ───────────────────────────────────────────────────────
  (packages
   (append
    (list
     vim git iw usbutils font-terminus tuigreet)
    %base-packages))))
