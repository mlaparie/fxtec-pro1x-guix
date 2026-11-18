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
;;; sides writing (bindfs, owners mapped), attached inside Android after
;;; each of its starts and never mounted under ~/.local/share/waydroid on
;;; the phone's side: deleting Waydroid's data cannot reach them.

(define-module (fxtec-pro1x services waydroid)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages waydroid)
  #:use-module (fxtec-pro1x packages waydroid-bt)
  #:autoload   (fxtec-pro1x packages misc) (modem-manager-1.24)
  #:use-module (gnu packages base)          ; coreutils, grep, glibc (getent)
  #:use-module (gnu packages bash)          ; bash-minimal
  #:use-module ((gnu packages commencement) #:select (gcc-toolchain))
  #:use-module ((gnu packages file-systems) #:select (bindfs))
  #:use-module ((gnu packages gawk) #:select (gawk))
  #:use-module (gnu packages linux)         ; util-linux, fuse, procps
  #:use-module ((gnu packages admin) #:select (inetutils)) ; logger
  #:use-module (gnu services)
  #:use-module (gnu services dbus)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
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
  ;; Mesa's tiled rendering in Android (#t, its default), or untiled
  ;; (#f): worth a try when an Android app with 3D elements is very slow;
  ;; some 3D elements and icons may then not be drawn.
  (gpu-tiling? waydroid-gpu-tiling? (default #t))
  ;; Apps (package names) rendered untiled while the rest stays tiled:
  ;; the way to speed up one slow 3D app without the side effects.
  (untiled-apps waydroid-untiled-apps (default '()))
  ;; Limits on Android, against a runaway app slowing the phone: its memory
  ;; ("3G", or #f: none), the cores it may use (4: the four slower ones,
  ;; #f: all), and its CPU priority against the phone's own processes
  ;; ('normal, 'low, 'lowest).  Quick actions' Waydroid menu changes them
  ;; until reboot.  The GPU cannot be limited this way.
  (memory-limit waydroid-memory-limit (default #f))
  (cpu-cores waydroid-cpu-cores (default #f))
  (cpu-priority waydroid-cpu-priority (default 'normal))
  ;; Bluetooth LE in Android through the phone's adapter, which BlueZ
  ;; keeps (waydroid-host-stack: phone keys, sensors; no audio), and the
  ;; phone's GPS position for Android apps.  Only with Waydroid's LineageOS
  ;; 20 image; with another they do nothing.
  (bluetooth? waydroid-bluetooth? (default #t))
  (gps? waydroid-gps? (default #t))
  ;; The phone's folders shown in Android's storage: (SOURCE . TARGET),
  ;; SOURCE relative to the user's home or absolute.
  (shared-folders waydroid-shared-folders
                  (default '(("Documents" . "Documents")
                             ("Downloads" . "Download")
                             ("Music" . "Music")
                             ("Pictures" . "Pictures")
                             ("Videos" . "Movies")
                             ("/tmp" . "tmp")))))

;;; The helper attaching a share inside Android's mount namespace.
(define pro1x-nsbind
  (computed-file "pro1x-nsbind"
    (with-imported-modules '((guix build utils))
      #~(begin
          (use-modules (guix build utils))
          (setenv "PATH" (string-append #$gcc-toolchain "/bin"))
          ;; What a profile with the toolchain would set.
          (setenv "C_INCLUDE_PATH" (string-append #$gcc-toolchain "/include"))
          (setenv "LIBRARY_PATH" (string-append #$gcc-toolchain "/lib"))
          (invoke "gcc" "-O2" "-Wall" "-o" #$output
                  #$(local-file
                     (repository-file "device/waydroid/pro1x-nsbind.c")))))))

(define pro1x-waydroid-share-script
  (program-file "pro1x-waydroid-share"
    #~(begin
        (setenv "NSBIND" #$pro1x-nsbind)
        (setenv "PATH"
                (string-append #$coreutils "/bin:" #$grep "/bin:"
                               #$util-linux "/bin:" #$util-linux "/sbin:"
                               #$bindfs "/bin:" #$fuse "/bin:"
                               #$glibc "/bin:" #$procps "/bin:"
                               #$inetutils "/bin:"
                               ;; waydroid, for its shell (watch).
                               "/run/current-system/profile/bin"))
        (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
               #$(local-file (repository-file "device/waydroid/pro1x-waydroid-share"))
               (cdr (command-line))))))

(define pro1x-waydroid-props-script
  (program-file "pro1x-waydroid-props"
    #~(begin
        (setenv "PATH"
                (string-append #$coreutils "/bin:" #$gawk "/bin:"
                               #$util-linux "/bin:"
                               ;; waydroid, to rebuild Android's properties.
                               "/run/current-system/profile/bin"))
        (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
               #$(local-file (repository-file "device/waydroid/pro1x-waydroid-props"))
               (cdr (command-line))))))

(define (waydroid-props-shepherd-service config)
  (shepherd-service
   (provision '(waydroid-props))
   (requirement '(file-systems))
   (one-shot? #t)
   (documentation "Mesa's rendering mode in Waydroid's Android (gpu-tiling?,
untiled-apps).")
   (start #~(lambda _
              (zero? (apply system* #$pro1x-waydroid-props-script
                            #$(if (waydroid-gpu-tiling? config)
                                  "tiled" "untiled")
                            '#$(waydroid-untiled-apps config)))))))

(define (waydroid-share-arguments config)
  (append (list (waydroid-user config)
                (or (waydroid-storage-view config) ""))
          (append-map (lambda (pair) (list (car pair) (cdr pair)))
                      (waydroid-shared-folders config))))

(define pro1x-waydroid-limits-script
  (program-file "pro1x-waydroid-limits"
    #~(begin
        (setenv "PATH"
                (string-append #$coreutils "/bin:" #$grep "/bin:"
                               #$inetutils "/bin"))
        (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
               #$(local-file (repository-file "device/sway/pro1x-waydroid-limits"))
               (cdr (command-line))))))

(define (waydroid-limits-shepherd-service config)
  (shepherd-service
   (provision '(waydroid-limits))
   (requirement '(file-systems))
   (documentation "Limits on Waydroid's Android at each of its starts:
memory-limit, cpu-cores, cpu-priority.")
   (start #~(make-forkexec-constructor
             (list #$pro1x-waydroid-limits-script "watch")
             #:log-file "/var/log/waydroid-limits.log"))
   (stop #~(make-kill-destructor))))

(define pro1x-waydroid-bt-script
  (program-file "pro1x-waydroid-bt"
    #~(begin
        (setenv "PATH"
                (string-append #$coreutils "/bin:" #$grep "/bin:" #$sed "/bin:"
                               #$e2fsprogs "/sbin:" #$inetutils "/bin:"
                               #$(file-append modem-manager-1.24 "/bin") ":"
                               "/run/current-system/profile/bin"))
        (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
               #$(local-file (repository-file "device/waydroid/pro1x-waydroid-bt"))
               (cdr (command-line))))))

;; waydroid-host-stack's bridge, and the overlay's setup then the watch of
;; Android's starts (device/waydroid/pro1x-waydroid-bt).
(define (waydroid-bt-shepherd-services config)
  (if (waydroid-bluetooth? config)
      (list
       (shepherd-service
        (provision '(waydroid-bt-host))
        (requirement '(dbus-system bluetooth))
        (documentation "Answer Waydroid's Bluetooth HAL through BlueZ.")
        (start #~(make-forkexec-constructor
                  (list #$(file-append waydroid-host-stack "/bin/waydroid-bt-host")
                        "--socket" "/run/waydroid-bt/host.sock")
                  #:log-file "/var/log/waydroid-bt-host.log"))
        (stop #~(make-kill-destructor)))
       (shepherd-service
        (provision '(waydroid-bt))
        (requirement '(file-systems waydroid-bt-host))
        (documentation "Bluetooth's files in Waydroid's overlay; at each
Android start, its permissions and, with gps?, the phone's position.")
        (start #~(lambda args
                   (system* #$pro1x-waydroid-bt-script "setup"
                            #$waydroid-bt-overlay)
                   (apply (make-forkexec-constructor
                           (list #$pro1x-waydroid-bt-script "watch"
                                 #$@(if (waydroid-gps? config) '("gps") '()))
                           #:log-file "/var/log/waydroid-bt.log")
                          args)))
        (stop #~(make-kill-destructor))))
      '()))

(define (waydroid-shepherd-services config)
  (cons* (waydroid-props-shepherd-service config)
         (waydroid-limits-shepherd-service config)
         (append (waydroid-share-shepherd-services config)
                 (waydroid-bt-shepherd-services config))))

(define (waydroid-share-shepherd-services config)
  (if (or (waydroid-storage-view config)
          (pair? (waydroid-shared-folders config)))
      (let ((args (waydroid-share-arguments config)))
        (list
         (shepherd-service
          (provision '(waydroid-share))
          (requirement '(file-systems))
          (documentation "Folders shared with Waydroid's Android:
storage-view and shared-folders.")
          (start #~(lambda args
                     (apply system* #$pro1x-waydroid-share-script
                            "start" '#$args)
                     ;; Then, at each Android start, the shares into its
                     ;; storage service (pro1x-waydroid-share).
                     (apply (make-forkexec-constructor
                             (cons* #$pro1x-waydroid-share-script "watch"
                                    '#$args)
                             #:log-file "/var/log/waydroid-share.log")
                            args)))
          (stop #~(lambda (pid . _)
                    ((make-kill-destructor) pid)
                    (apply system* #$pro1x-waydroid-share-script
                           "stop" '#$args)
                    #f)))))
      '()))

(define (waydroid-etc config)
  `(,@(if (waydroid-bluetooth? config)
          ;; waydroid-bt-host's socket directory, the same path inside.
          `(("waydroid-bt/lxc-mount.conf"
             ,(plain-file "lxc-mount.conf"
                          "lxc.mount.entry = /run/waydroid-bt run/waydroid-bt none rbind,create=dir,optional 0 0\n")))
          '())
    ("pro1x/waydroid.conf"
     ,(plain-file "waydroid.conf"
                  (string-append
                   "# Written by waydroid-service-type (config.scm).\n"
                   "AUTOSTART="
                   (if (waydroid-autostart? config) "yes" "no") "\n"
                   ;; pro1x-waydroid-limits' defaults.
                   "MEMORY_LIMIT=" (or (waydroid-memory-limit config) "none") "\n"
                   "CPU_CORES=" (match (waydroid-cpu-cores config)
                                  (#f "all")
                                  (n (number->string n))) "\n"
                   "CPU_PRIORITY=" (symbol->string (waydroid-cpu-priority config))
                   "\n")))))

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
