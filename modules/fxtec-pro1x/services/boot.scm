;;; fxtec-pro1x/services/boot.scm — boot menu split + boot-slot success marking
;;; Translates modules/boot-menu.nix and modules/boot-success.nix.

(define-module (fxtec-pro1x services boot)
  #:use-module (fxtec-pro1x packages misc)   ; qbootctl
  #:use-module (fxtec-pro1x files)           ; repository-file
  #:use-module (gnu packages bash)
  #:use-module (gnu packages base)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages linux)          ; e2fsprogs, inotify-tools
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-boot-menu-configuration
            pro1x-boot-menu-configuration?
            make-pro1x-boot-menu-configuration
            pro1x-boot-menu-service-type
            pro1x-boot-success-configuration
            pro1x-boot-success-configuration?
            make-pro1x-boot-success-configuration
            pro1x-boot-success-service-type
            pro1x-rootfs-resize-service-type))

;;; ── Boot menu ───────────────────────────────────────────────────────────────

(define-record-type* <pro1x-boot-menu-configuration>
  pro1x-boot-menu-configuration make-pro1x-boot-menu-configuration
  pro1x-boot-menu-configuration?
  ;; How many "Boot previous generation N" entries to write.
  ;; Must equal the value compiled into U-Boot (make-u-boot-pro1x).
  (generations pro1x-boot-menu-generations (default 4))
  ;; Seconds U-Boot's menu counts down at each boot before the current system
  ;; (0: none, -1: wait for a key).  Takes effect at the next boot, no reflash: it is
  ;; in menu.env.
  (delay pro1x-boot-menu-delay (default 15)))

;;; device/boot/pro1x-boot-menu.  Guix's extlinux.conf has no "Default" entry,
;;; unlike NixOS's in modules/boot-menu.nix: the current system is entry 1, then
;;; older generations newest first (gnu/bootloader/extlinux.scm), so previous
;;; generation N is entry N+1.
(define (pro1x-boot-menu-split-script config)
  (let ((n (number->string (pro1x-boot-menu-generations config)))
        (delay (number->string (pro1x-boot-menu-delay config))))
    (program-file "pro1x-boot-menu-split"
      #~(begin
          (setenv "PATH" (string-append #$coreutils "/bin:" #$gawk "/bin:"
                                        #$sed "/bin"))
          (apply execl #$(file-append bash-minimal "/bin/sh") "sh"
                 #$(local-file (repository-file "device/boot/pro1x-boot-menu"))
                 (append
                  ;; /boot is a mount of its own: the encrypted layout's plain
                  ;; area, which pro1x-boot-area found (services/fde.scm).
                  (if (= (stat:dev (stat "/boot")) (stat:dev (stat "/")))
                      '("/boot/extlinux/extlinux.conf" "/boot/extlinux")
                      '("--plain-area" "/boot" "/boot/extlinux/extlinux.conf"
                        "/boot/boot/extlinux"))
                  (list #$n #$delay)))))))

(define (pro1x-boot-menu-shepherd-services config)
  (if (> (pro1x-boot-menu-generations config) 0)
      (let ((split (pro1x-boot-menu-split-script config)))
        (list
         ;; Not in file-systems: the system does not say which layout it is on,
         ;; and a file system there that is not found stops `guix system
         ;; reconfigure' and delays the boot.  A system that cannot mount it still
         ;; runs: only the boot menu's updates depend on it.
         (shepherd-service
          (provision '(pro1x-boot-area))
          (requirement '(root-file-system))
          (one-shot? #t)
          (documentation "Mount the plain area of an encrypted phone at /boot,
if this phone has one.")
          (start
           #~(lambda _
               (false-if-exception (mkdir "/boot"))
               (when (= (stat:dev (stat "/boot")) (stat:dev (stat "/")))
                 (system* #$(file-append util-linux "/bin/mount")
                          "-o" "noatime" "-L" "guixboot" "/boot"))
               #t)))
         ;; Not a one-shot: the slots must follow every rewrite of
         ;; extlinux.conf (deploy, reconfigure, and delete-generations,
         ;; roll-back, switch-generation run on the phone), not only boot.
         (shepherd-service
          (provision '(pro1x-boot-menu))
          (requirement '(file-systems pro1x-boot-area))
          (documentation "Write the U-Boot menu's files under /boot
at start and whenever extlinux.conf changes.")
          (start
           #~(make-forkexec-constructor
              (list #$(pro1x-boot-menu-watch-script split))
              #:log-file "/var/log/pro1x-boot-menu.log"))
          (stop #~(make-kill-destructor))
          (respawn? #t))))
      '()))

;;; Run SPLIT, then again each time extlinux.conf is written or renamed
;;; into place (Guix writes a temporary file and renames it).
(define (pro1x-boot-menu-watch-script split)
  (program-file
   "pro1x-boot-menu-watch"
   #~(begin
       (use-modules (ice-9 popen) (ice-9 rdelim))
       ;; A new plain area has no extlinux/ until Guix first writes there.
       (false-if-exception (mkdir "/boot/extlinux"))
       (system* #$split)
       (let ((events (open-pipe* OPEN_READ
                                 #$(file-append inotify-tools
                                                "/bin/inotifywait")
                                 "-m" "-q" "-e" "close_write" "-e" "moved_to"
                                 "--format" "%f" "/boot/extlinux")))
         (let loop ()
           (let ((file (read-line events)))
             (unless (eof-object? file)
               (when (string=? file "extlinux.conf")
                 (system* #$split))
               (loop))))))))

(define pro1x-boot-menu-service-type
  (service-type
   (name 'pro1x-boot-menu)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-boot-menu-shepherd-services)))
   (default-value (pro1x-boot-menu-configuration))
   (description "Write /boot/extlinux/prev1.conf to prevN.conf so the U-Boot
menu's 'Boot previous generation' entries work.  N must match what was compiled
into U-Boot via make-u-boot-pro1x.")))

;;; ── Boot success ────────────────────────────────────────────────────────────

(define-record-type* <pro1x-boot-success-configuration>
  pro1x-boot-success-configuration make-pro1x-boot-success-configuration
  pro1x-boot-success-configuration?
  (qbootctl-package pro1x-boot-success-qbootctl (default qbootctl)))

(define (pro1x-boot-success-shepherd-services config)
  (let ((qbc (pro1x-boot-success-qbootctl config)))
    (list
     (shepherd-service
      (provision '(pro1x-boot-success))
      (requirement '(udev file-systems))
      (documentation "Mark the Qualcomm A/B boot slot as successful")
      (one-shot? #t)
      (start
       #~(make-forkexec-constructor
          (list "/bin/sh" "-c"
                (string-append
                 #$(file-append qbc "/bin/qbootctl") " -m || "
                 #$(file-append qbc "/bin/qbootctl") " -m 0"))
          #:log-file "/var/log/pro1x-boot-success.log"))
      (stop #~(make-kill-destructor))))))

(define (pro1x-boot-success-packages config)
  (list (pro1x-boot-success-qbootctl config)))

(define pro1x-boot-success-service-type
  (service-type
   (name 'pro1x-boot-success)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-boot-success-shepherd-services)
     (service-extension profile-service-type
                        pro1x-boot-success-packages)))
   (default-value (pro1x-boot-success-configuration))
   (description "Mark the active A/B boot slot as successfully booted.
Without this, the ABL falls back to fastboot after a hard reboot.")))

;;; ── Rootfs resize ───────────────────────────────────────────────────────────

(define (pro1x-rootfs-resize-shepherd-services _)
  (list
   (shepherd-service
    (provision '(pro1x-rootfs-resize))
    (requirement '(file-systems))
    (documentation "Expand the root file system to fill its partition if needed")
    (one-shot? #t)
    (start
     #~(make-forkexec-constructor
        (list "/bin/sh" "-c"
              (string-append
               ;; btrfs grows online, and not at all when it fills the
               ;; device already.
               "if [ \"$(awk '$2==\"/\" {print $3; exit}' /proc/mounts)\" = btrfs ]; then "
               "exec " #$(file-append btrfs-progs "/bin/btrfs")
               " filesystem resize max /; fi; "
               ;; ext4: locate root device.
               "dev=$(awk '$2==\"/\" {print $1; exit}' /proc/mounts) || exit 1; "
               ;; /dev/mapper/pro1x-crypt is dm-0 in /proc/partitions.
               "dev=$(readlink -f \"$dev\"); "
               ;; Partition size in 1 KiB blocks (from /proc/partitions).
               "devname=${dev##*/}; "
               "pblocks=$(awk -v d=\"$devname\" '$4==d {print $3}' /proc/partitions); "
               ;; Filesystem block count (4 KiB blocks, from tune2fs).
               "fsblocks=$("
               #$(file-append e2fsprogs "/sbin/tune2fs") " -l \"$dev\""
               " | awk '/^Block count:/ {print $3}'); "
               ;; Mirror Droidian's threshold: resize if gap > 10000 * 4 KiB (~40 MiB).
               "diff=$((pblocks - 4 * fsblocks)); "
               "if [ \"$diff\" -gt 10000 ]; then "
               #$(file-append e2fsprogs "/sbin/resize2fs") " -f \"$dev\"; "
               "fi"))
        #:log-file "/var/log/pro1x-rootfs-resize.log"))
    (stop #~(make-kill-destructor)))
   ;; The image's files are uncompressed (CI's mkfs.btrfs --compress wrote
   ;; extents the kernel could not read), and the phone only compresses what
   ;; it writes.  So compress the store and /home once, at low priority,
   ;; through a second mount of the volume: Guix mounts /gnu/store read-only.
   ;; /home is a subvolume, which -r does not enter, hence its own pass.
   ;; Snapshots wait for the mark (services/snapshots.scm): rewriting /home
   ;; after one would take the space twice.  The mark is set however it
   ;; ends, so they do not wait forever; the log has the status.
   (shepherd-service
    (provision '(pro1x-rootfs-compress))
    (requirement '(file-systems))
    (documentation "Compress a btrfs root once, after the flash")
    (one-shot? #t)
    (start
     #~(make-forkexec-constructor
        (list "/bin/sh" "-c"
              (string-append
               "done=/var/lib/pro1x/rootfs-compressed; "
               "[ -e $done ] && exit 0; "
               "[ \"$(awk '$2==\"/\" {print $3; exit}' /proc/mounts)\" = btrfs ] || exit 0; "
               "dev=$(awk '$2==\"/\" {print $1; exit}' /proc/mounts); "
               "m=/run/pro1x-rootfs-compress; mkdir -p $m; "
               #$(file-append util-linux "/bin/mount")
               " -o subvolid=5 \"$dev\" $m"
               " || { mkdir -p ${done%/*}; echo mount-failed > $done; exit 1; }; "
               #$(file-append coreutils "/bin/nice") " -n 19 "
               #$(file-append util-linux "/bin/ionice") " -c 3 "
               #$(file-append btrfs-progs "/bin/btrfs")
               " filesystem defragment -r -czstd $m/gnu $m/home; s=$?; "
               #$(file-append util-linux "/bin/umount") " $m; rmdir $m; "
               "mkdir -p ${done%/*}; echo $s > $done; "
               "exit $s"))
        #:log-file "/var/log/pro1x-rootfs-compress.log"))
    (stop #~(make-kill-destructor)))))

(define pro1x-rootfs-resize-service-type
  (service-type
   (name 'pro1x-rootfs-resize)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-rootfs-resize-shepherd-services)))
   (default-value #f)
   (description "Expand the root file system to fill its partition: btrfs
always (a no-op once full), ext4 when the gap between partition size and
filesystem size exceeds ~40 MiB, as the resize_userdata_if_needed logic from
Droidian's initramfs-tools-halium.")))
