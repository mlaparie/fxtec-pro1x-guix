;;; fxtec-pro1x/services/keyboard.scm — keyd + XKB layout + dconf persistence

(define-module (fxtec-pro1x services keyboard)
  #:use-module (gnu packages gnome)         ; dconf
  #:use-module (gnu packages linux)         ; keyd
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services configuration)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-keyboard-configuration
            pro1x-keyboard-configuration?
            make-pro1x-keyboard-configuration
            pro1x-keyboard-service-type))

(define-record-type* <pro1x-keyboard-configuration>
  pro1x-keyboard-configuration make-pro1x-keyboard-configuration
  pro1x-keyboard-configuration?
  (xkb-layout  pro1x-keyboard-xkb-layout  (default "us"))
  (xkb-variant pro1x-keyboard-xkb-variant (default "intl")))

;;; /etc/keyd/default.conf
(define (pro1x-keyboard-etc config)
  (let* ((layout  (pro1x-keyboard-xkb-layout  config))
         (variant (pro1x-keyboard-xkb-variant config))
         ;; dconf xkb source: "us+intl" when variant present, else just "us"
         (xkb-source (if (string-null? variant)
                         layout
                         (string-append layout "+" variant))))
    (list
     `("keyd/default.conf"
       ,(local-file "../../device/input/keyd.conf" "keyd.conf"))
     ;; dconf system-db that persists the XKB layout across reboots.
     `("dconf/profile/user"
       ,(plain-file "dconf-profile-user"
                    "user-db:user\nsystem-db:local\n"))
     ;; Compiled here: /etc/dconf is a read-only store link, so
     ;; `dconf update' at activation cannot write /etc/dconf/db/local.
     `("dconf/db/local"
       ,(pro1x-dconf-db
         "dconf-db-local"
         (plain-file "00-keyboard"
                     (string-append
                      "[org/gnome/desktop/input-sources]\n"
                      "sources=[('xkb', '" xkb-source "')]\n")))))))

;;; Compile the dconf keyfile KEYFILE into a GVariant database, like
;;; dconf-profile->db in (gnu services xorg).
(define (pro1x-dconf-db name keyfile)
  (computed-file
   name
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils))
         (mkdir "keyfiles")
         (symlink #$keyfile "keyfiles/00-keyfile")
         (invoke #$(file-append dconf "/bin/dconf") "compile"
                 #$output "keyfiles")))))

;;; Shepherd service for keyd daemon
(define (pro1x-keyboard-shepherd-services config)
  (list
   (shepherd-service
    (provision '(keyd))
    (requirement '(udev))
    (documentation "keyd — keyboard Fn-layer remapping for the Pro1X")
    (start
     #~(make-forkexec-constructor
        (list #$(file-append keyd "/bin/keyd"))
        #:log-file "/var/log/keyd.log"))
    (stop #~(make-kill-destructor))
    (respawn? #t))))

(define (pro1x-keyboard-packages config)
  (list keyd dconf))

(define pro1x-keyboard-service-type
  (service-type
   (name 'pro1x-keyboard)
   (extensions
    (list
     (service-extension etc-service-type          pro1x-keyboard-etc)
     (service-extension shepherd-root-service-type pro1x-keyboard-shepherd-services)
     (service-extension profile-service-type       pro1x-keyboard-packages)))
   (default-value (pro1x-keyboard-configuration))
   (description "Hardware keyboard support for the F(x)tec Pro1X: keyd Fn-layer
remapping, XKB layout, and dconf system-db so the layout survives reboots.")))
