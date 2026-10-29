;;; fxtec-pro1x/system/common.scm — what the Pro¹x systems share
;;;
;;; Root SSH by key, for guix deploy from a PC (scripts/deploy.sh): the
;;; key pair is made on the PC when the phone is flashed (scripts/flash.sh,
;;; ~/.ssh/pro1x-guix).  A system built with ROOT-SSH-KEYS (public key
;;; files) lets root in with them and puts the first one in new users'
;;; homes as ~/.ssh/pro1x-guix.pub, so the owner's own configuration can
;;; refer to it.
;;;
;;; /etc/guix/config.scm: a starting configuration for the phone's owner.
;;; It inherits the port's system from the channel, so guix pull still
;;; brings the port's fixes; root SSH is off in it until the owner
;;; uncomments one line (opt-in), and it holds no key, so it can be shared
;;; as a dotfile.
;;;
;;; State: template evaluated on the PC for the three systems, with and
;;; without the key line; not yet used on the phone.

(define-module (fxtec-pro1x system common)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:export (pro1x-root-authorized-keys
            pro1x-root-key-skeletons
            pro1x-user-config-service))

(define (pro1x-root-authorized-keys keys)
  "Return openssh authorized-keys entries letting root in with KEYS, a list
of public key files."
  (if (null? keys)
      '()
      `(("root" ,@keys))))

(define (pro1x-root-key-skeletons keys)
  "Return skeleton entries putting the first of KEYS in new homes as
~/.ssh/pro1x-guix.pub."
  (if (null? keys)
      '()
      `((".ssh/pro1x-guix.pub" ,(car keys)))))

(define (pro1x-user-config module procedure)
  "Return the text of /etc/guix/config.scm for the system that PROCEDURE, a
symbol exported by MODULE, a list of symbols, returns."
  (string-append
   ";;; /etc/guix/config.scm — starting point for your own configuration of
;;; this phone, written by the fxtec-pro1x channel.  To use it:
;;;
;;;   cp /etc/guix/config.scm /etc/guix/channels.scm ~/.config/guix/
;;;   guix pull                # then log out and back in once
;;;   sudo guix system reconfigure ~/.config/guix/config.scm
;;;
;;; The port's system comes from the channel, so guix pull brings its fixes;
;;; your changes stay in this file.

(use-modules (gnu)
             " (with-output-to-string (lambda () (write module))) ")

(define base
  (" (symbol->string procedure) "
   ;; Root SSH login by key lets `guix deploy` from a PC update this phone
   ;; (scripts/deploy.sh in the fxtec-pro1x-guix repository).  It is off
   ;; until you uncomment the line below.  ~/.ssh/pro1x-guix.pub is the
   ;; PC's key, put in your home when the phone was flashed; the path is
   ;; relative to this file.
   ;; #:root-ssh-keys (list (local-file \"../../.ssh/pro1x-guix.pub\"))
   ))

(operating-system
  (inherit base)
  ;; Your changes, for example:
  ;; (timezone \"Europe/Paris\")
  ;; (packages (cons (specification->package \"htop\")
  ;;                 (operating-system-packages base)))
  ;; (services (cons (service some-service-type)
  ;;                 (operating-system-user-services base)))
  )
"))

(define (pro1x-user-config-service module procedure)
  "Return a service installing /etc/guix/config.scm for PROCEDURE in MODULE."
  (simple-service 'pro1x-user-config etc-service-type
                  `(("guix/config.scm"
                     ,(plain-file "config.scm"
                                  (pro1x-user-config module procedure))))))
