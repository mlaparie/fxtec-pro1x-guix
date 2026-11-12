;;; Waydroid's system side: the package, its bus policy and activation file
;;; (D-Bus starts `waydroid -w container start' as root on the first call to
;;; id.waydro.Container), and its polkit actions.  Upstream does the same
;;; without systemd (USE_SYSTEMD=0).  Images and state live in
;;; /var/lib/waydroid once `sudo waydroid init' has run.

(define-module (fxtec-pro1x services waydroid)
  #:use-module (fxtec-pro1x packages waydroid)
  #:use-module (gnu services)
  #:use-module (gnu services dbus)
  #:export (waydroid-service-type))

(define waydroid-service-type
  (service-type
   (name 'waydroid)
   (extensions
    (list (service-extension dbus-root-service-type (const (list waydroid)))
          (service-extension polkit-service-type (const (list waydroid)))
          (service-extension profile-service-type (const (list waydroid)))))
   (default-value #f)
   (description "Waydroid, Android in an LXC container: its bus policy,
D-Bus activation of the container manager, and polkit actions.")))
