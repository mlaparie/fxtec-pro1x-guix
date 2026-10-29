;;; fxtec-pro1x/services/hardware.scm — core hardware service type
;;;
;;; Translates modules/hardware.nix.  In Guix the kernel, bootloader and
;;; firmware live in the operating-system record rather than a service, so
;;; pro1x-hardware-service-type handles what CAN be a service:
;;;
;;;   • udev rules (cameras, haptics, slider)
;;;   • kernel parameters
;;;   • feedbackd group
;;;   • optional USB serial getty
;;;   • touch calibration matrix for display gaps
;;;
;;; The operating-system record in systems/ provides the kernel, firmware and
;;; bootloader directly — see systems/minimal.scm.

(define-module (fxtec-pro1x services hardware)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu system accounts)
  #:use-module (gnu system shadow)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (srfi srfi-1)
  #:export (pro1x-hardware-configuration
            pro1x-hardware-configuration?
            make-pro1x-hardware-configuration
            pro1x-hardware-service-type))

(define-record-type* <pro1x-hardware-configuration>
  pro1x-hardware-configuration make-pro1x-hardware-configuration
  pro1x-hardware-configuration?
  ;; Display gap (rows to black out at top/bottom for rounded corners / dead rows)
  (display-top-gap    pro1x-hardware-display-top-gap    (default 0))
  (display-bottom-gap pro1x-hardware-display-bottom-gap (default 0))
  ;; Enable USB serial gadget console (ttyGS0) as rescue line
  (serial-enable?     pro1x-hardware-serial-enable?     (default #f))
  ;; Extra kernel verbosity (earlycon, ignore_loglevel)
  (verbose?           pro1x-hardware-verbose?           (default #f))
  ;; fbcon rotation: 0 portrait, 1 clockwise, 2 upside-down, 3 CCW
  (console-rotation   pro1x-hardware-console-rotation   (default #f)))

(define (pro1x-udev-rules config)
  ;; Returns a file-like object: the base rules optionally extended with a
  ;; touch calibration matrix rule when display gaps are configured.
  (let* ((top    (pro1x-hardware-display-top-gap    config))
         (bottom (pro1x-hardware-display-bottom-gap config))
         (gap?   (> (+ top bottom) 0))
         (base   (local-file "../../../device/udev/60-pro1x.rules"
                             "60-pro1x.rules")))
    (if gap?
        (let* ((even   (lambda (g) (- g (modulo g 2))))
               (gtop   (even top))
               (gbot   (even bottom))
               (active (- 2160 gtop gbot))
               (scale  (exact->inexact (/ 2160 active)))
               (offset (exact->inexact (/ (- gtop) active)))
               (touch-rule
                (string-append
                 "ACTION!=\"remove\", SUBSYSTEM==\"input\","
                 " ENV{ID_INPUT_TOUCHSCREEN}==\"1\","
                 " ENV{LIBINPUT_CALIBRATION_MATRIX}=\""
                 "1 0 0 0 " (number->string scale) " " (number->string offset) "\"\n")))
          (mixed-text-file "60-pro1x.rules" base touch-rule))
        base)))

(define (pro1x-hardware-account-groups config)
  (list (user-group (name "feedbackd") (system? #t))))

(define (pro1x-hardware-etc config)
  ;; Nothing in /etc for the base hardware layer; udev rules go via the udev
  ;; extension.  Left as a hook for callers that want to extend.
  '())

(define pro1x-hardware-service-type
  (service-type
   (name 'pro1x-hardware)
   (extensions
    (list
     ;; udev rules: dma-buf, haptics, slider symlink, optional touch matrix
     ;; udev only reads lib/udev/rules.d/ inside each item: a bare rules
     ;; file is silently ignored, hence file->udev-rule.
     (service-extension udev-service-type
                        (lambda (config)
                          (list (file->udev-rule "60-pro1x.rules"
                                                 (pro1x-udev-rules config)))))
     ;; feedbackd group (vibration motor)
     (service-extension account-service-type
                        pro1x-hardware-account-groups)))
   (default-value (pro1x-hardware-configuration))
   (description "Core hardware support for the F(x)tec Pro1X: udev rules for
cameras, haptics, GPIO slider, and optional touch calibration for display gaps.")))
