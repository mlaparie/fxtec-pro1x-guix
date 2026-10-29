;;; fxtec-pro1x/services/camera.scm — camera stack via libcamera-pro1x
;;; Translates modules/camera.nix.

(define-module (fxtec-pro1x services camera)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages video)       ; v4l-utils
  #:use-module (gnu packages gnome)       ; snapshot (GNOME camera)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-camera-configuration
            pro1x-camera-configuration?
            make-pro1x-camera-configuration
            pro1x-camera-service-type))

(define-record-type* <pro1x-camera-configuration>
  pro1x-camera-configuration make-pro1x-camera-configuration
  pro1x-camera-configuration?)

;;; /etc/xdg/user-dirs.defaults — system-wide FreeDesktop default XDG dirs.
;;; xdg-user-dirs-update reads this on first login to initialise ~/.config/user-dirs.dirs.
;;; NixOS equivalent: environment.etc."xdg/user-dirs.defaults".text = ...
;;; Using xdg/ (not skel/) because in Guix, /etc/skel is an immutable store symlink.
(define (pro1x-camera-etc config)
  (list
   `("xdg/user-dirs.defaults"
     ,(plain-file "user-dirs.defaults"
                  "DESKTOP=Desktop\n\
DOWNLOAD=Downloads\n\
DOCUMENTS=Documents\n\
MUSIC=Music\n\
PICTURES=Pictures\n\
VIDEOS=Videos\n"))))

;;; WirePlumber finds the patched libcamera through LD_LIBRARY_PATH, set
;;; by pro1x-audio-session in (fxtec-pro1x services audio): an
;;; /etc/environment.d file did that on NixOS, but nothing reads it here.

(define (pro1x-camera-packages config)
  (list libcamera-pro1x cameractrl v4l-utils))

(define pro1x-camera-service-type
  (service-type
   (name 'pro1x-camera)
   (extensions
    (list
     (service-extension etc-service-type
                        pro1x-camera-etc)
     (service-extension profile-service-type
                        pro1x-camera-packages)))
   (default-value (pro1x-camera-configuration))
   (description "Camera support for the F(x)tec Pro1X: libcamera with IMX582/S5K4H7
patches, cameractrl for manual focus/exposure, v4l-utils, and XDG user dir defaults.")))
