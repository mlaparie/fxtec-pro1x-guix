;;; Waydroid's system side: the package, its bus policy and activation file
;;; (D-Bus starts `waydroid -w container start' as root on the first call to
;;; id.waydro.Container), and its polkit actions.  Upstream does the same
;;; without systemd (USE_SYSTEMD=0).  Images and state live in
;;; /var/lib/waydroid once `sudo waydroid init' has run.
;;;
;;; The window mode is set here, not in Android: the one-shot service
;;; waydroid-settings writes it into waydroid.cfg's [properties] at boot,
;;; and `waydroid upgrade -o' makes it a default property of the image.
;;; pro1x-waydroid-admin starts the service again after a download.  A value
;;; set inside Android (`waydroid prop set') would win over it, so the
;;; quick-actions menu does not offer one.
;;;
;;; Without Waydroid: (delete waydroid-service-type) in config.scm's
;;; modify-services.  A downloaded image stays in /var/lib/waydroid.
;;;
;;; State: the D-Bus activation and polkit policy are installed on the phone
;;; (generation 32); waydroid-settings not yet run there.

(define-module (fxtec-pro1x services waydroid)
  #:use-module (fxtec-pro1x packages waydroid)
  #:use-module (gnu services)
  #:use-module (gnu services dbus)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (waydroid-configuration
            waydroid-configuration?
            waydroid-service-type))

(define-record-type* <waydroid-configuration>
  waydroid-configuration make-waydroid-configuration
  waydroid-configuration?
  ;; One window per Android app (#t), or all of Android in one window (#f).
  (multi-windows? waydroid-multi-windows? (default #f)))

(define (waydroid-shepherd-services config)
  (let ((line (string-append "persist.waydroid.multi_windows = "
                             (if (waydroid-multi-windows? config)
                                 "true" "false"))))
    (list
     (shepherd-service
      (provision '(waydroid-settings))
      (requirement '(file-systems))
      (documentation "Apply config.scm's Waydroid settings to its image")
      (one-shot? #t)
      (modules '((ice-9 rdelim) (srfi srfi-1)))
      (start
       #~(lambda _
           (let ((cfg "/var/lib/waydroid/waydroid.cfg")
                 (prop "/var/lib/waydroid/waydroid_base.prop"))
             (define (lines file)
               (call-with-input-file file
                 (lambda (port)
                   (let loop ((acc '()))
                     (let ((l (read-line port)))
                       (if (eof-object? l) (reverse acc) (loop (cons l acc))))))))
             (define (key? l)
               (string-prefix? "persist.waydroid.multi_windows" l))
             ;; Nothing to do before `waydroid init'.
             (when (file-exists? cfg)
               (let* ((old (remove key? (lines cfg)))
                      (new (if (member "[properties]" old)
                               (append-map (lambda (l)
                                             (if (string=? l "[properties]")
                                                 (list l #$line)
                                                 (list l)))
                                           old)
                               (append old (list "" "[properties]" #$line)))))
                 (call-with-output-file cfg
                   (lambda (port)
                     (for-each (lambda (l) (display l port) (newline port))
                               new))))
               ;; The image's default properties, made again only if they
               ;; differ: base.prop has "key=value", without spaces.
               (unless (and (file-exists? prop)
                            (member (string-delete #\space #$line) (lines prop)))
                 (system* #$(file-append waydroid "/bin/waydroid")
                          "upgrade" "-o")))
             #t)))
      (respawn? #f)))))

(define waydroid-service-type
  (service-type
   (name 'waydroid)
   (extensions
    (list (service-extension dbus-root-service-type (const (list waydroid)))
          (service-extension polkit-service-type (const (list waydroid)))
          (service-extension profile-service-type (const (list waydroid)))
          (service-extension shepherd-root-service-type
                             waydroid-shepherd-services)))
   (default-value (waydroid-configuration))
   (description "Waydroid, Android in an LXC container: its bus policy,
D-Bus activation of the container manager, polkit actions, and the window
mode from config.scm.")))
