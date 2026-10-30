;;; fxtec-pro1x/home.scm — a Guix Home environment for the Pro¹x user
;;;
;;; Files in $HOME come in three kinds (author, 2026-10-30):
;;;   managed   symlinked from the store by Guix Home; replaced on every
;;;             deploy; edit them in config.scm, not on the phone.
;;;   seeded    copied once, when missing; afterwards they are the user's
;;;             and Guix never touches them again.
;;;   unmanaged everything else.
;;;
;;; Used from the system configuration, so scripts/deploy.sh deploys the
;;; home environment together with the system (guix-home-service-type
;;; activates it at boot and on reconfigure):
;;;
;;;   (service guix-home-service-type
;;;            `(("user" ,(pro1x-home
;;;                        #:managed `((".config/foot/foot.ini"
;;;                                     ,(local-file "foot.ini")))
;;;                        #:seeded `((".config/sway/config"
;;;                                    ,(file-append pro1x-sway-config
;;;                                                  "/share/pro1x-sway/config")))))))
;;;
;;; See docs/home.md.  State: written 2026-10-30; evaluates; not yet
;;; deployed to the phone.

(define-module (fxtec-pro1x home)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-1)
  #:export (pro1x-home
            home-seeded-files-service-type))

;; VALUE: a list of (PATH FILE-LIKE), PATH relative to $HOME.  At each
;; activation, copy FILE-LIKE to PATH if nothing is there (not even a
;; dangling link), writable by the user.
(define (seeded-files-activation files)
  #~(begin
      (use-modules (guix build utils))
      (for-each
       (lambda (entry)
         (let ((target (string-append (getenv "HOME") "/" (car entry))))
           (unless (false-if-exception (lstat target))
             (mkdir-p (dirname target))
             (copy-recursively (cadr entry) target)
             (chmod target (if (file-is-directory? target) #o755 #o644))
             (format #t "seeded ~a~%" target))))
       (list #$@(map (lambda (entry)
                       #~(list #$(first entry) #$(second entry)))
                     files)))))

(define home-seeded-files-service-type
  (service-type
   (name 'home-seeded-files)
   (extensions
    (list (service-extension home-activation-service-type
                             (lambda (files)
                               (with-imported-modules '((guix build utils))
                                 (seeded-files-activation files))))))
   (compose concatenate)
   (extend append)
   (default-value '())
   (description "Copy files into the home directory once, when missing.")))

(define* (pro1x-home #:key (managed '()) (seeded '()) (packages '())
                     (services '()))
  "Return a home environment with MANAGED files (list of (PATH FILE-LIKE),
symlinked by Guix Home), SEEDED files (copied once when missing),
PACKAGES in the user's home profile, and any further SERVICES."
  (home-environment
   (packages packages)
   (services
    (append
     (if (null? managed)
         '()
         (list (simple-service 'pro1x-managed-files home-files-service-type
                               managed)))
     (if (null? seeded)
         '()
         (list (service home-seeded-files-service-type seeded)))
     services))))
