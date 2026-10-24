;;; systems/minimal.scm — minimal Pro1X Guix system
;;;
;;; Build and deploy:
;;;   guix system image --system=aarch64-linux systems/minimal.scm
;;;
;;; Or on an aarch64 machine / via offloading:
;;;   guix system reconfigure systems/minimal.scm
;;;
;;; Flash (after building u-boot-pro1x separately):
;;;   See scripts/flash.sh

(use-modules (gnu)
             (gnu bootloader extlinux)
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
             (fxtec-pro1x services hardware)
             (fxtec-pro1x services keyboard)
             (fxtec-pro1x services modem)
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
     ;; UART console (debug) + framebuffer console, loglevel quiet
     "console=ttyMSM0,115200n8"
     "console=tty1"
     "loglevel=4"
     ;; USB CDC gadget with fixed MACs for stable PC interface name
     "g_cdc.host_addr=02:50:31:e8:00:01"
     "g_cdc.dev_addr=02:50:31:e8:00:02")
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
    (bootloader extlinux-bootloader)
    ;; U-Boot looks for extlinux.conf via sysboot on the ext4 userdata partition.
    (targets '("/dev/disk/by-partlabel/userdata"))
    (menu-entries '())           ; extra entries managed by pro1x-boot-menu
    (timeout 3)))

  ;; ── Filesystems ───────────────────────────────────────────────────────────
  (file-systems
   (cons*
    ;; Root on the userdata partition (ext4, ~50 GB).
    ;; Label set by scripts/flash.sh.
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
     (service network-manager-service-type)
     (service wpa-supplicant-service-type)

     ;; SSH for USB-ethernet access
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #t)   ; tighten after adding keys
               (permit-root-login 'prohibit-password))))

    ;; Base Guix services
    %base-services))

  ;; ── System packages ───────────────────────────────────────────────────────
  (packages
   (append
    (list
     vim git iw usbutils)
    %base-packages)))
