;;; systems/mobile.scm — the Pro¹x mobile system, as shipped
;;;
;;; The system itself is (fxtec-pro1x system mobile) in the channel; this
;;; file adds root's SSH key for scripts/deploy.sh.  Used by
;;; scripts/flash.sh, scripts/deploy.sh and CI.

(use-modules (gnu)
             (ice-9 textual-ports)
             (fxtec-pro1x system mobile))

;; Root SSH keys for scripts/deploy.sh, one per line of keys/pro1x-guix.pub.
;; That file is not in git: each owner puts their own public key there
;; (README, "Updating without reflashing").  Without it, root has no SSH
;; login.  The keys also go into /etc/guix/config.scm on the phone.
(define %root-ssh-keys
  (let ((file (string-append (dirname (or (current-filename) "systems/."))
                             "/../keys/pro1x-guix.pub")))
    (if (file-exists? file)
        (filter (lambda (line) (not (string-null? line)))
                (map string-trim-both
                     (string-split (call-with-input-file file get-string-all)
                                   #\newline)))
        '())))

(pro1x-mobile-operating-system #:root-ssh-keys %root-ssh-keys)
