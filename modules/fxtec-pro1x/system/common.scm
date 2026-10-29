;;; fxtec-pro1x/system/common.scm — what the Pro¹x systems share
;;;
;;; Root SSH by key, for guix deploy from a PC (scripts/deploy.sh): the
;;; key pair is made on the PC when the phone is flashed (scripts/flash.sh,
;;; ~/.ssh/pro1x-guix).  A system built with ROOT-SSH-KEYS (public key
;;; files) lets root in with them and puts the first one in new users'
;;; homes as ~/.ssh/pro1x-guix.pub, so the owner's own configuration can
;;; refer to it.
;;;
;;; /etc/guix/config.scm and /etc/guix/channels.scm: starting files for the
;;; phone's owner (channels: see (fxtec-pro1x services channels)).
;;; config.scm inherits the port's system from the channel, so guix pull still
;;; brings the port's fixes; root SSH is off in it until the owner
;;; uncomments one line (opt-in), and it holds no key, so it can be shared
;;; as a dotfile.
;;;
;;; State: template evaluated on the PC for the three systems, with and
;;; without the key line; not yet used on the phone.

(define-module (fxtec-pro1x system common)
  #:use-module (fxtec-pro1x services channels)
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
  "Return a service installing /etc/guix/config.scm for PROCEDURE in MODULE,
and /etc/guix/channels.scm.

Not through etc-service-type: an /etc entry under guix/ would turn the whole
of /etc/guix into a read-only store link and hide the acl and signing keys
Guix writes there.  Like guix-service-type for its channels.scm, link each
file in place at activation."
  (define files
    `(("config.scm" ,(plain-file "config.scm"
                                 (pro1x-user-config module procedure)))
      ("channels.scm" ,pro1x-channels-file)))

  (simple-service
   'pro1x-guix-files activation-service-type
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils))
         (mkdir-p "/etc/guix")
         (for-each
          (lambda (name file)
            (let ((target (string-append "/etc/guix/" name)))
              ;; A link into the store is ours from an earlier generation;
              ;; anything else was written by hand: keep it as .bak.
              (when (false-if-exception (lstat target))
                (if (and (symbolic-link? target)
                         (store-file-name? (readlink target)))
                    (delete-file target)
                    (rename-file target (string-append target ".bak"))))
              (symlink file target)))
          '#$(map car files)
          (list #$@(map cadr files)))))))
