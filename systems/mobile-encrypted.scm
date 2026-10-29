;;; systems/mobile-encrypted.scm — the Pro¹x mobile-encrypted system, as shipped
;;;
;;; The system itself is (fxtec-pro1x system mobile-encrypted) in the channel.

(use-modules (gnu)
             (guix gexp)
             (fxtec-pro1x system mobile-encrypted))

;; Root SSH key for scripts/deploy.sh.  keys/pro1x-guix.pub is not in git:
;; each owner puts their own public key there (README, "Updating without
;; reflashing").  Without it, root has no SSH login.
(define %root-ssh-keys
  (let ((file (string-append (dirname (or (current-filename) "systems/."))
                             "/../keys/pro1x-guix.pub")))
    (if (file-exists? file)
        `(("root" ,(local-file (canonicalize-path file) "pro1x-guix.pub")))
        '())))

(pro1x-mobile-encrypted-operating-system #:root-ssh-keys %root-ssh-keys)
