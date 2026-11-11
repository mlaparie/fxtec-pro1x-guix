;;; fxtec-pro1x/services/snapshots.scm — snapshots of /home with btrbk
;;;
;;; On a btrfs root (the images since 2026-11-08), /home is its own subvolume
;;; (made by CI's mkfs.btrfs --subvol): btrbk snapshots it into /.snapshots,
;;; read-only, without the system, which Guix's generations already roll
;;; back.  Sized for a phone's storage: a snapshot only costs what changed
;;; since; btrbk takes one only when /home changed (snapshot_create
;;; onchange), keeps every one of the last day, then one a day for a week and
;;; one a week for three weeks.  Hourly, so a suspended phone catches up when
;;; it wakes.  Nested subvolumes are not in a snapshot: the restore makes
;;; ~/.cache and ~/.local/share/flatpak subvolumes (scripts/backup-phone.sh),
;;; so the cache's churn and the Flatpak apps (reinstallable) take no
;;; snapshot space.  On an ext4 root, or without the /home subvolume: nothing.
;;;
;;; A file from a snapshot: /.snapshots/home.YYYYMMDDTHHMM/user/...
;;; The list: sudo btrbk -c /etc/btrbk/btrbk.conf list snapshots
;;;
;;; State: build-tested only.

(define-module (fxtec-pro1x services snapshots)
  #:use-module (gnu packages backup)        ; btrbk
  #:use-module (gnu packages linux)         ; btrfs-progs, util-linux
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-snapshots-configuration
            pro1x-snapshots-configuration?
            pro1x-snapshots-service-type))

(define-record-type* <pro1x-snapshots-configuration>
  pro1x-snapshots-configuration make-pro1x-snapshots-configuration
  pro1x-snapshots-configuration?
  ;; When btrbk runs, as cron fields.
  (schedule pro1x-snapshots-schedule (default "0 * * * *"))
  ;; btrbk's retention, see btrbk.conf(5).
  (preserve-min pro1x-snapshots-preserve-min (default "1d"))
  (preserve pro1x-snapshots-preserve (default "7d 3w")))

(define (pro1x-btrbk-conf config)
  (plain-file "btrbk.conf"
              (string-append "\
# Written by pro1x-snapshots-service-type (config.scm).
timestamp_format        long
snapshot_create         onchange
snapshot_preserve_min   " (pro1x-snapshots-preserve-min config) "
snapshot_preserve       " (pro1x-snapshots-preserve config) "

volume /
  snapshot_dir .snapshots
  subvolume home
")))

(define (pro1x-snapshots-program config)
  (program-file
   "pro1x-snapshots"
   #~(begin
       (use-modules (ice-9 popen) (ice-9 rdelim))
       (define (mkdir-p* dir)
         (unless (file-exists? dir) (mkdir dir #o700)))
       (define (output . command)
         (let* ((port (apply open-pipe* OPEN_READ command))
                (text (read-line port)))
           (close-pipe port)
           (if (eof-object? text) "" text)))
       ;; Only on a btrfs root whose /home is a subvolume.
       (when (and (string=? "btrfs"
                            (output #$(file-append util-linux "/bin/findmnt")
                                    "-no" "FSTYPE" "/"))
                  (zero? (system* #$(file-append btrfs-progs "/bin/btrfs")
                                  "-q" "subvolume" "show" "/home")))
         (mkdir-p* "/.snapshots")
         (exit (status:exit-val
                (system* #$(file-append btrbk "/bin/btrbk")
                         "-c" "/etc/btrbk/btrbk.conf" "-q" "run")))))))

(define (pro1x-snapshots-shepherd-services config)
  (list
   (shepherd-service
    (provision '(pro1x-snapshots))
    (requirement '(file-systems))
    (documentation "Snapshot /home with btrbk, hourly when it changed.")
    (modules '((shepherd service timer)))
    (start #~(make-timer-constructor
              (cron-string->calendar-event #$(pro1x-snapshots-schedule config))
              (command (list #$(pro1x-snapshots-program config)))
              #:log-file "/var/log/pro1x-snapshots.log"))
    (stop #~(make-timer-destructor))
    (actions (list (shepherd-action
                    (inherit shepherd-trigger-action)
                    (documentation "Run btrbk now, without waiting.")))))))

(define pro1x-snapshots-service-type
  (service-type
   (name 'pro1x-snapshots)
   (extensions
    (list (service-extension shepherd-root-service-type
                             pro1x-snapshots-shepherd-services)
          (service-extension etc-service-type
                             (lambda (config)
                               `(("btrbk/btrbk.conf"
                                  ,(pro1x-btrbk-conf config)))))
          (service-extension profile-service-type
                             (const (list btrbk btrfs-progs)))))
   (default-value (pro1x-snapshots-configuration))
   (description "Snapshot /home with btrbk on a btrfs root, with a
retention sized for a phone.")))
