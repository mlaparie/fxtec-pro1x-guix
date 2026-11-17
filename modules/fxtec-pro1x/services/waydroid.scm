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
;;;
;;; Shared folders (pro1x-waydroid-share, at boot): Android's internal
;;; storage at storage-view (/mnt/waydroid), owned there by the user; and
;;; shared-folders, the phone's folders shown in Android's storage, both
;;; sides writing (bindfs, owners mapped).  Both need Android set up and
;;; started once: before that, nothing is mounted.

(define-module (fxtec-pro1x services waydroid)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages waydroid)
  #:use-module (gnu packages base)          ; coreutils, grep, glibc (getent)
  #:use-module (gnu packages bash)          ; bash-minimal
  #:use-module ((gnu packages file-systems) #:select (bindfs))
  #:use-module (gnu packages linux)         ; util-linux, fuse
  #:use-module (gnu services)
  #:use-module (gnu services dbus)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (srfi srfi-1)
  #:export (waydroid-configuration
            waydroid-configuration?
            waydroid-service-type))

(define-record-type* <waydroid-configuration>
  waydroid-configuration make-waydroid-configuration
  waydroid-configuration?
  ;; Start Android when the user logs in?
  (autostart? waydroid-autostart? (default #f))
  ;; The user whose Waydroid it is, and where its Android storage shows on
  ;; the phone (#f: nowhere).
  (user waydroid-user (default "user"))
  (storage-view waydroid-storage-view (default "/mnt/waydroid"))
  ;; The phone's folders shown in Android's storage: (SOURCE . TARGET),
  ;; SOURCE relative to the user's home or absolute.
  (shared-folders waydroid-shared-folders
                  (default '(("Documents" . "Documents")
                             ("Downloads" . "Download")
                             ("Music" . "Music")
                             ("Pictures" . "Pictures")
                             ("Videos" . "Movies")
                             ("/tmp" . "tmp")))))

(define pro1x-waydroid-share-script
  (program-file "pro1x-waydroid-share"
    #~(begin
        (setenv "PATH"
                (string-append #$coreutils "/bin:" #$grep "/bin:"
                               #$util-linux "/bin:" #$util-linux "/sbin:"
                               #$bindfs "/bin:" #$fuse "/bin:"
                               #$glibc "/bin"))
        (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
               #$(local-file (repository-file "device/waydroid/pro1x-waydroid-share"))
               (cdr (command-line))))))

(define (waydroid-share-arguments config)
  (append (list (waydroid-user config)
                (or (waydroid-storage-view config) ""))
          (append-map (lambda (pair) (list (car pair) (cdr pair)))
                      (waydroid-shared-folders config))))

(define (waydroid-shepherd-services config)
  (if (or (waydroid-storage-view config)
          (pair? (waydroid-shared-folders config)))
      (let ((args (waydroid-share-arguments config)))
        (list
         (shepherd-service
          (provision '(waydroid-share))
          (requirement '(file-systems))
          (documentation "Folders shared with Waydroid's Android:
storage-view and shared-folders.")
          (start #~(lambda _
                     (zero? (apply system* #$pro1x-waydroid-share-script
                                   "start" '#$args))))
          (stop #~(lambda _
                    (apply system* #$pro1x-waydroid-share-script
                           "stop" '#$args)
                    #f)))))
      '()))

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
          (service-extension etc-service-type waydroid-etc)
          (service-extension shepherd-root-service-type
                             waydroid-shepherd-services)))
   (default-value (waydroid-configuration))
   (description "Waydroid, Android in an LXC container: its bus policy,
D-Bus activation of the container manager, polkit actions, whether
Android starts at login, and folders shared with it.")))
