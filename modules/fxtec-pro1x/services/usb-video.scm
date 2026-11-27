;;; fxtec-pro1x/services/usb-video.scm — the screen as a USB webcam
;;;
;;; Puts pro1x-usb-video in the system profile and gives root a Shepherd
;;; service that switches the USB gadget: `herd start pro1x-usb-video'
;;; replaces the built-in g_cdc by the configfs composite gadget (the same
;;; network and serial, plus the UVC camera), `herd stop pro1x-usb-video'
;;; puts g_cdc back.  Not started at boot unless at-boot? is #t: the switch
;;; re-enumerates the USB device, and g_cdc is the rescue link.  The user
;;; then runs pro1x-usb-video start in the Sway session.
;;;
;;; The kernel needs CONFIG_USB_CONFIGFS_F_UVC (device/kernel/pro1x-7.3.fragment).
;;; State: written 2026-11-27, not yet run on the phone.

(define-module (fxtec-pro1x services usb-video)
  #:use-module (fxtec-pro1x packages usb-video)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-usb-video-configuration
            pro1x-usb-video-configuration?
            pro1x-usb-video-at-boot?
            pro1x-usb-video-service-type))

(define-record-type* <pro1x-usb-video-configuration>
  pro1x-usb-video-configuration make-pro1x-usb-video-configuration
  pro1x-usb-video-configuration?
  ;; Make the composite gadget (network, serial, camera) at boot instead
  ;; of g_cdc.  Off by default: a change to the USB rescue link.
  (at-boot? pro1x-usb-video-at-boot? (default #f)))

(define (pro1x-usb-video-shepherd-services config)
  (let ((gadget (file-append pro1x-usb-video "/bin/pro1x-usb-gadget")))
    (list
     (shepherd-service
      (provision '(pro1x-usb-video))
      (requirement '(udev pro1x-usb-network))
      (documentation "USB gadget with the screen as a UVC camera (configfs);
stopped, the built-in g_cdc gadget is back.")
      (start #~(lambda _
                 (zero? (system* #$gadget "video"))))
      (stop #~(lambda _
                (system* #$gadget "network")
                #f))
      (auto-start? (pro1x-usb-video-at-boot? config))
      (respawn? #f)))))

(define pro1x-usb-video-service-type
  (service-type
   (name 'pro1x-usb-video)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-usb-video-shepherd-services)
     (service-extension profile-service-type
                        (const (list pro1x-usb-video)))))
   (default-value (pro1x-usb-video-configuration))
   (description "The phone's screen as a USB webcam: pro1x-usb-video in the
profile, and a Shepherd service that switches the USB gadget to the
composite one with the UVC camera (start) and back to g_cdc (stop).")))
