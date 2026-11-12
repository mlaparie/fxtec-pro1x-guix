;;; Waydroid's system side: the package, its bus policy and activation file
;;; (D-Bus starts `waydroid container start' as root on the first call to
;;; id.waydro.Container), and its polkit actions.  Upstream does the same
;;; without systemd (USE_SYSTEMD=0).  Images and state live in
;;; /var/lib/waydroid once `sudo waydroid init' has run.
;;;
;;; autostart? starts Android at login, in Sway and in Phosh
;;; (`pro1x-waydroid autostart' reads /etc/pro1x/waydroid.conf), once an
;;; image is downloaded.  With "Sleep when unused" on in the quick-actions
;;; menu, Android then freezes after its screen timeout while none of its
;;; apps is shown.
;;;
;;; Without Waydroid: (delete waydroid-service-type) in config.scm's
;;; modify-services.  A downloaded image stays in /var/lib/waydroid.

(define-module (fxtec-pro1x services waydroid)
  #:use-module (fxtec-pro1x packages waydroid)
  #:use-module (gnu services)
  #:use-module (gnu services dbus)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (waydroid-configuration
            waydroid-configuration?
            waydroid-service-type))

(define-record-type* <waydroid-configuration>
  waydroid-configuration make-waydroid-configuration
  waydroid-configuration?
  ;; Start Android when the user logs in?
  (autostart? waydroid-autostart? (default #f)))

(define (waydroid-etc config)
  `(("pro1x/waydroid.conf"
     ,(plain-file "waydroid.conf"
                  (string-append
                   "# Written by waydroid-service-type (config.scm).\n"
                   "AUTOSTART="
                   (if (waydroid-autostart? config) "yes" "no") "\n")))))

(define waydroid-service-type
  (service-type
   (name 'waydroid)
   (extensions
    (list (service-extension dbus-root-service-type (const (list waydroid)))
          (service-extension polkit-service-type (const (list waydroid)))
          (service-extension profile-service-type (const (list waydroid)))
          (service-extension etc-service-type waydroid-etc)))
   (default-value (waydroid-configuration))
   (description "Waydroid, Android in an LXC container: its bus policy,
D-Bus activation of the container manager, polkit actions, and whether
Android starts at login.")))
