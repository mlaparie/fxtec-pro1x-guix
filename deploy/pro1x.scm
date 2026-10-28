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
;;; ~/.ssh/pro1x-guix on the host, a key used for nothing else.
;;;
;;; The host's signing key (/etc/guix/signing-key.pub) is added to the
;;; deployed system's guix-configuration authorized-keys.  guix deploy
;;; writes it to /etc/guix/acl before copying, but activating the new
;;; system rewrites the ACL from authorized-keys; without the key there,
;;; the copy for the bootloader step is refused ("unauthorized public key")
;;; and extlinux.conf is not updated.
;;;
;;; Provenance: guix deploy records the deploying guix's channels (all of
;;; the host's, from `guix describe') in the new generation.  Here it records
;;; only guix and nonguix from the host, plus fxtec-pro1x at this tree's git
;;; HEAD (uncommitted changes are not visible in it).
;;;
;;; Environment:
;;;   PRO1X_SYSTEM  system file to deploy (default systems/mobile.scm)
;;;   PRO1X_HOST    phone address (default 172.16.42.1)
;;;   PRO1X_IDENTITY  private key (default ~/.ssh/pro1x-guix)
;;;
;;; State: first used 2026-10-28.  Encrypted systems also need
;;; scripts/update-encrypted-boot.sh afterwards (plain boot area).

(use-modules (gnu machine)
             (gnu machine ssh)
             (gnu services)
             (gnu services base)
             (gnu system)
             (guix channels)
             (guix gexp)
             (guix ui)                  ; load*
             (fxtec-pro1x services channels)
             (ice-9 popen)
             (ice-9 rdelim)
             (srfi srfi-1))

(define %system-file
  (or (getenv "PRO1X_SYSTEM") "systems/mobile.scm"))

(define (git-head)
  (let* ((port (open-pipe* OPEN_READ "git" "rev-parse" "HEAD"))
         (commit (read-line port)))
    (close-pipe port)
    commit))

(define (deployed-channels channels)
  "Return guix and nonguix from CHANNELS, the host's, and fxtec-pro1x at
this tree's HEAD."
  (append (filter (lambda (c) (memq (channel-name c) '(guix nonguix)))
                  channels)
          (list (channel
                 (inherit %fxtec-pro1x-channel)
                 (commit (git-head))))))

;; guix deploy calls current-channels when it adds the provenance.
(let* ((describe (resolve-module '(guix describe)))
       (host-channels (module-ref describe 'current-channels)))
  (module-set! describe 'current-channels
               (lambda () (deployed-channels (host-channels)))))

(define (with-host-signing-key os)
  "Return OS with this host's signing key among the Guix authorized keys."
  (operating-system
    (inherit os)
    (services
     (modify-services (operating-system-user-services os)
       (guix-service-type
        config => (guix-configuration
                   (inherit config)
                   (authorized-keys
                    (cons (local-file "/etc/guix/signing-key.pub"
                                      "host-signing-key.pub")
                          (guix-configuration-authorized-keys config)))))))))

(list
 (machine
  (operating-system
   (with-host-signing-key
    (load* (canonicalize-path %system-file) '())))
  (environment managed-host-environment-type)
  (configuration
   (machine-ssh-configuration
    (host-name (or (getenv "PRO1X_HOST") "172.16.42.1"))
    (system "aarch64-linux")
    (user "root")
    (identity (or (getenv "PRO1X_IDENTITY")
                  (string-append (getenv "HOME") "/.ssh/pro1x-guix")))))))
