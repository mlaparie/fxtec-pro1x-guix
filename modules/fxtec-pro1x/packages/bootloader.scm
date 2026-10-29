;;; fxtec-pro1x/packages/bootloader.scm — extlinux.conf for U-Boot
;;;
;;; U-Boot on the Pro¹x reads /boot/extlinux/extlinux.conf itself (sysboot),
;;; so nothing has to be installed on disk: the bootloader only writes that
;;; file.  pro1x-extlinux-bootloader is Guix's u-boot-bootloader (extlinux
;;; configuration, no package, no installer) without its disk-image
;;; installer, so neither deploy, reconfigure nor image builds write to a
;;; partition.
;;;
;;; Its name stays 'u-boot on purpose.  `guix system delete-generations',
;;; `roll-back' and `switch-generation' look the bootloader up by the name
;;; recorded in the system, among the bootloaders the running guix knows;
;;; the phone's guix does not include this channel.  Under 'u-boot they find
;;; Guix's u-boot-bootloader, which writes the same extlinux.conf with no
;;; package to build, and nothing else (reinstall-bootloader passes no
;;; target devices).  The earlier name 'extlinux found Guix's
;;; extlinux-bootloader, whose syslinux does not build for aarch64.
;;;
;;; State: `guix system switch-generation 26' on the phone, with the phone's
;;; own guix (5ceffb6), rewrote extlinux.conf (2026-10-29).  Generations
;;; deployed before this record recorded 'extlinux and still fail there.
;;; The U-Boot slots (prev1-3) are refreshed at boot or with
;;; `herd start pro1x-boot-menu', not by these commands.

(define-module (fxtec-pro1x packages bootloader)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader u-boot)
  #:export (pro1x-extlinux-bootloader))

(define pro1x-extlinux-bootloader
  (bootloader
   (inherit u-boot-bootloader)
   (disk-image-installer #f)))
