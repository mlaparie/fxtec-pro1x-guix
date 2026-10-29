;;; systems/mobile.scm — the Pro¹x mobile system, as shipped
;;;
;;; The system itself is (fxtec-pro1x system mobile) in the channel; this
;;; file adds root's SSH key for scripts/deploy.sh.  Used by
;;; scripts/flash.sh, scripts/deploy.sh and CI.

(use-modules (gnu)
             (guix gexp)
             (fxtec-pro1x system mobile))

;; Root SSH key for scripts/deploy.sh.  keys/pro1x-guix.pub is not in git:
;; each owner puts their own public key there (README, "Updating without
;; reflashing").  Without it, root has no SSH login.
(define %root-ssh-keys
  (let ((file (string-append (dirname (or (current-filename) "systems/."))
                             "/../keys/pro1x-guix.pub")))
    (if (file-exists? file)
        `(("root" ,(local-file (canonicalize-path file) "pro1x-guix.pub")))
        '())))

(pro1x-mobile-operating-system #:root-ssh-keys %root-ssh-keys)
