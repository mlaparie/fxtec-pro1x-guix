;;; fxtec-pro1x/services/camera.scm — camera stack via libcamera-pro1x
;;; Translates modules/camera.nix.

(define-module (fxtec-pro1x services camera)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages video)       ; v4l-utils
  #:use-module (gnu packages gnome)       ; snapshot (GNOME camera)
  #:use-module (gnu packages linux)       ; kmod
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
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

;;; A sensor that does not answer while it probes is gone until its driver
;;; is loaded again, and camss registers no camera at all without it: on
;;; 2026-11-05, imx582's chip id read timed out on the CCI bus at boot
;;; ("Error reading reg 0x0016: -110"), and the camera app found none until
;;; the module was reloaded by hand.  So, once at boot: wait for the sensor
;;; drivers, and reload any whose subdevice is missing, up to three times.
(define pro1x-camera-sensors-program
  (program-file
   "pro1x-camera-sensors"
   #~(begin
       (use-modules (ice-9 ftw) (ice-9 rdelim))
       (define modprobe #$(file-append kmod "/bin/modprobe"))
       (define (loaded? module)
         (file-exists? (string-append "/sys/module/" module)))
       (define (present? module)        ;a v4l subdevice named after it
         (any (lambda (dev)
                (let ((name (false-if-exception
                             (call-with-input-file
                                 (string-append "/sys/class/video4linux/" dev
                                                "/name")
                               read-line))))
                  (and (string? name) (string-prefix? module name))))
              (or (scandir "/sys/class/video4linux"
                           (lambda (f) (string-prefix? "v4l-subdev" f)))
                  '())))
       (define (any pred lst)
         (and (pair? lst) (or (pred (car lst)) (any pred (cdr lst)))))
       (setvbuf (current-output-port) 'line)
       ;; udev loads them some 25 s into the boot.
       (let wait ((n 0))
         (unless (or (> n 90) (and (loaded? "imx582") (loaded? "s5k4h7")))
           (sleep 1)
           (wait (+ n 1))))
       (sleep 5)                        ;their probes
       (for-each
        (lambda (module)
          (let retry ((tries 0))
            (cond ((not (loaded? module))
                   (format #t "~a: not loaded~%" module))
                  ((present? module)
                   (when (> tries 0)
                     (format #t "~a: there after ~a reload(s)~%" module tries)))
                  ((< tries 3)
                   (format #t "~a: no subdevice, reloading~%" module)
                   (system* modprobe "-r" module)
                   (system* modprobe module)
                   (sleep 3)
                   (retry (+ tries 1)))
                  (else (format #t "~a: still missing~%" module)))))
        '("imx582" "s5k4h7")))))

(define (pro1x-camera-shepherd-services config)
  (list (shepherd-service
         (provision '(pro1x-camera-sensors))
         (requirement '(udev))
         (documentation "Reload a camera sensor driver whose probe failed at boot.")
         ;; Not one-shot: it runs up to two minutes, and ends by itself.
         (respawn? #f)
         (start #~(make-forkexec-constructor
                   (list #$pro1x-camera-sensors-program)
                   #:log-file "/var/log/pro1x-camera-sensors.log")))))

(define pro1x-camera-service-type
  (service-type
   (name 'pro1x-camera)
   (extensions
    (list
     (service-extension etc-service-type
                        pro1x-camera-etc)
     (service-extension shepherd-root-service-type
                        pro1x-camera-shepherd-services)
     (service-extension profile-service-type
                        pro1x-camera-packages)))
   (default-value (pro1x-camera-configuration))
   (description "Camera support for the F(x)tec Pro1X: libcamera with IMX582/S5K4H7
patches, cameractrl for manual focus/exposure, v4l-utils, and XDG user dir defaults.")))
