;;; deploy/pro1x.scm — guix deploy target: the Pro1X over USB Ethernet
;;;
;;; Used by scripts/deploy.sh.  Builds on the host (QEMU binfmt for
;;; aarch64), copies the closure as root over SSH, makes it the new system
;;; generation, activates it (like guix system reconfigure: /etc, accounts,
;;; new Shepherd services) and rewrites /boot/extlinux/extlinux.conf.
;;; Kernel, initrd and firmware changes need a reboot.  The previous
;;; generations stay in the U-Boot menu.
;;;
;;; Needs on the phone: root SSH login with ~/.ssh/pro1x-guix.pub, the key
;;; scripts/flash.sh made on this host (systems/*.scm read it).  Its private
;;; key is ~/.ssh/pro1x-guix, a key used for nothing else.  The deployed
;;; system keeps that key in root's authorized keys even when the system
;;; file does not list it (the owner's config.scm leaves root SSH off), or
;;; a deploy of the owner's configuration would lock the next one out.
;;;
;;; The host's signing key (/etc/guix/signing-key.pub) is added to the
;;; deployed system's guix-configuration authorized-keys.  guix deploy
;;; writes it to /etc/guix/acl before copying, but activating the new
;;; system rewrites the ACL from authorized-keys; without the key there,
;;; the copy for the bootloader step is refused ("unauthorized public key")
;;; and extlinux.conf is not updated.
;;;
;;; Provenance: guix deploy records the deploying guix's channels in the new
;;; generation.  scripts/deploy.sh runs it under the phone's channels
;;; (guix time-machine), so these are the phone's; with --repo, this host's,
;;; where only guix and nonguix are kept.  fxtec-pro1x is recorded at this
;;; tree's git HEAD when HEAD is on origin/main, since -L modules builds
;;; from this tree (uncommitted changes are not visible in it).  An unpushed
;;; HEAD is left out: guix deploy checks each recorded
;;; channel against the phone's by fetching its URL, where that commit does
;;; not exist ("object not found").  allow-downgrades? turns a deploy of an
;;; older tree into a warning instead of an error.
;;;
;;; Environment:
;;;   PRO1X_SYSTEM  system file to deploy (default systems/mobile.scm)
;;;   PRO1X_PHONE_CHANNELS  set by scripts/deploy.sh when guix runs with
;;;                 the phone's channels: keep them all in the provenance
;;;   PRO1X_HOST    phone address (default 172.16.42.1)
;;;   PRO1X_IDENTITY  private key (default ~/.ssh/pro1x-guix)
;;;
;;; State: first used 2026-10-28.  Encrypted systems also need
;;; scripts/update-encrypted-boot.sh afterwards (plain boot area).

(use-modules (gnu machine)
             (gnu machine ssh)
             (gnu services)
             (gnu services base)
             (gnu services ssh)
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

(define (head-pushed?)
  (zero? (status:exit-val
          (system* "git" "merge-base" "--is-ancestor" "HEAD" "origin/main"))))

(define (deployed-channels channels)
  "Return CHANNELS without fxtec-pro1x, and fxtec-pro1x at this tree's HEAD
if it is pushed.  Under the phone's channels (scripts/deploy.sh) all of them
are kept; with this host's own guix (--repo), only guix and nonguix."
  (append (filter (lambda (c)
                    (and (not (eq? (channel-name c) 'fxtec-pro1x))
                         (or (getenv "PRO1X_PHONE_CHANNELS")
                             (memq (channel-name c) '(guix nonguix)))))
                  channels)
          (if (head-pushed?)
              (list (channel
                     (inherit %fxtec-pro1x-channel)
                     (commit (git-head))))
              (begin
                (warning (G_ "HEAD is not on origin/main: fxtec-pro1x \
left out of the provenance~%"))
                '()))))

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

(define (with-root-ssh-key os)
  "Return OS letting root in with this host's ~/.ssh/pro1x-guix.pub."
  (operating-system
    (inherit os)
    (services
     (modify-services (operating-system-user-services os)
       (openssh-service-type
        config => (openssh-configuration
                   (inherit config)
                   (authorized-keys
                    (cons `("root" ,(local-file
                                     (string-append (getenv "HOME")
                                                    "/.ssh/pro1x-guix.pub")
                                     "pro1x-guix.pub"))
                          (openssh-configuration-authorized-keys
                           config)))))))))

(list
 (machine
  (operating-system
   (with-root-ssh-key
    (with-host-signing-key
     (load* (canonicalize-path %system-file) '()))))
  (environment managed-host-environment-type)
  (configuration
   (machine-ssh-configuration
    (host-name (or (getenv "PRO1X_HOST") "172.16.42.1"))
    (system "aarch64-linux")
    (user "root")
    (allow-downgrades? #t)
    (identity (or (getenv "PRO1X_IDENTITY")
                  (string-append (getenv "HOME") "/.ssh/pro1x-guix")))))))
