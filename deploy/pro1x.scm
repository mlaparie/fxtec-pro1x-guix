;;; deploy/pro1x.scm — guix deploy target: the Pro1X over USB Ethernet
;;;
;;; Used by scripts/deploy.sh.  Builds on the host (QEMU binfmt for
;;; aarch64), copies the closure as root over SSH, makes it the new system
;;; generation, activates it (like guix system reconfigure: /etc, accounts,
;;; new Shepherd services) and rewrites /boot/extlinux/extlinux.conf.
;;; Kernel, initrd and firmware changes need a reboot.  The previous
;;; generations stay in the U-Boot menu.
;;;
;;; Needs on the phone: root SSH login with keys/pro1x-guix.pub (set in the
;;; systems/*.scm openssh configuration).  Its private key is
;;; ~/.ssh/pro1x-guix on the host, a key used for nothing else.  The host's
;;; signing key is added to the phone's /etc/guix/acl by guix deploy itself
;;; (authorize? #t).
;;;
;;; Environment:
;;;   PRO1X_SYSTEM  system file to deploy (default systems/mobile.scm)
;;;   PRO1X_HOST    phone address (default 172.16.42.1)
;;;   PRO1X_IDENTITY  private key (default ~/.ssh/pro1x-guix)
;;;
;;; State: not tested yet.  Encrypted systems also need
;;; scripts/update-encrypted-boot.sh afterwards (plain boot area).

(use-modules (gnu machine)
             (gnu machine ssh)
             (guix ui))                 ; load*

(define %system-file
  (or (getenv "PRO1X_SYSTEM") "systems/mobile.scm"))

(list
 (machine
  (operating-system
   (load* (canonicalize-path %system-file) '()))
  (environment managed-host-environment-type)
  (configuration
   (machine-ssh-configuration
    (host-name (or (getenv "PRO1X_HOST") "172.16.42.1"))
    (system "aarch64-linux")
    (user "root")
    (identity (or (getenv "PRO1X_IDENTITY")
                  (string-append (getenv "HOME") "/.ssh/pro1x-guix")))))))
