;;; systems/mobile.scm — the Pro¹x mobile system, as shipped
;;;
;;; The system itself is (fxtec-pro1x system mobile) in the channel; this
;;; file adds root's SSH key for scripts/deploy.sh.  Used by
;;; scripts/flash.sh, scripts/deploy.sh and CI.

(use-modules (gnu)
             (guix gexp)
             (srfi srfi-1)
             (fxtec-pro1x system mobile))

;; Root SSH by key for scripts/deploy.sh: the PC key that scripts/flash.sh
;; makes (~/.ssh/pro1x-guix.pub), or, when this file is reconfigured on the
;; phone, the copy of it in the user's home.  Without either, root has no
;; SSH login.  The owner's own /etc/guix/config.scm keeps it off until
;; they opt in.
(define %root-ssh-keys
  (let ((file (find file-exists?
                    (list (string-append (or (getenv "HOME") "/root")
                                         "/.ssh/pro1x-guix.pub")
                          "/home/user/.ssh/pro1x-guix.pub"))))
    (if file
        (list (local-file file "pro1x-guix.pub"))
        '())))

(pro1x-mobile-operating-system #:root-ssh-keys %root-ssh-keys)
