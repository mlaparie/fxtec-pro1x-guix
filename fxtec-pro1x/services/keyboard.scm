;;; fxtec-pro1x/services/keyboard.scm — keyd + Finnish layout
;;; Translates modules/keyboard.nix.

(define-module (fxtec-pro1x services keyboard)
  #:use-module (gnu packages linux)       ; keyd
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
  ;; XKB layout applied by the compositor (phoc/Phosh reads this from dconf)
  (xkb-layout  pro1x-keyboard-xkb-layout  (default "fi"))
  (xkb-variant pro1x-keyboard-xkb-variant (default "nodeadkeys")))

;;; /etc/keyd/default.conf — wired in from device/input/keyd.conf
(define (pro1x-keyboard-etc config)
  (list `("keyd/default.conf"
          ,(local-file "../../device/input/keyd.conf" "keyd.conf"))))

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
  (list keyd))

(define pro1x-keyboard-service-type
  (service-type
   (name 'pro1x-keyboard)
   (extensions
    (list
     (service-extension etc-service-type    pro1x-keyboard-etc)
     (service-extension shepherd-root-service-type
                        pro1x-keyboard-shepherd-services)
     (service-extension profile-service-type pro1x-keyboard-packages)))
   (default-value (pro1x-keyboard-configuration))
   (description "Hardware keyboard support for the F(x)tec Pro1X: keyd Fn-layer
remapping from device/input/keyd.conf, Finnish XKB layout.")))
