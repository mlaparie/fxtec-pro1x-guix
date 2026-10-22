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
  pro1x-camera-configuration?
  ;; User account to create XDG dirs for
  (user pro1x-camera-user (default "user")))

;;; XDG user dirs are created at login by xdg-user-dirs-update; we place a
;;; seed config in /etc/skel so new users get Pictures/Videos from the start.
(define (pro1x-camera-etc config)
  (list
   `("skel/.config/user-dirs.dirs"
     ,(plain-file "user-dirs.dirs"
                  "XDG_DESKTOP_DIR=\"$HOME/Desktop\"
XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"
XDG_DOCUMENTS_DIR=\"$HOME/Documents\"
XDG_MUSIC_DIR=\"$HOME/Music\"
XDG_PICTURES_DIR=\"$HOME/Pictures\"
XDG_VIDEOS_DIR=\"$HOME/Videos\"
"))))

;;; WirePlumber needs to find our patched libcamera at runtime.
;;; We set LD_LIBRARY_PATH via /etc/environment.d/ which is read by PAM.
(define (pro1x-camera-ld-path-etc config)
  (list
   `("environment.d/51-pro1x-libcamera.conf"
     ,(computed-file "51-pro1x-libcamera.conf"
        #~(call-with-output-file #$output
            (lambda (port)
              (display
               (string-append "LD_LIBRARY_PATH="
                              #$libcamera-pro1x "/lib"
                              "\n")
               port)))))))

(define (pro1x-camera-packages config)
  (list libcamera-pro1x cameractrl v4l-utils))

(define pro1x-camera-service-type
  (service-type
   (name 'pro1x-camera)
   (extensions
    (list
     (service-extension etc-service-type
                        (lambda (config)
                          (append
                           (pro1x-camera-etc config)
                           (pro1x-camera-ld-path-etc config))))
     (service-extension profile-service-type
                        pro1x-camera-packages)))
   (default-value (pro1x-camera-configuration))
   (description "Camera support for the F(x)tec Pro1X: libcamera with IMX582/S5K4H7
patches, cameractrl for manual focus/exposure, v4l-utils, and XDG user dirs.")))
