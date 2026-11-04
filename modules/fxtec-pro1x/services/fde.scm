;;; fxtec-pro1x/services/fde.scm — offset LUKS2 root for the Pro¹x
;;;
;;; The userdata partition is laid out as:
;;;   [0, 512 MiB)  : plain ext4 labelled "guixboot" (kernels, initrds,
;;;                   extlinux.conf; readable by U-Boot without decryption)
;;;   [512 MiB, end)  : LUKS2 container (header + encrypted root ext4)
;;;
;;; 512 MiB: a kernel and its initrd are about 60 MiB, and the area holds the
;;; current system and three previous ones (services/boot.scm).
;;;
;;; A loop device exposes the container because `cryptsetup open' for LUKS2
;;; does not take --offset.  The initrd has no udev and no losetup: the partition
;;; is found through sysfs and the loop set up by pro1x-loop-offset, a small static
;;; program (the initrd's static Guile has no ioctl).  The rest is Guix's own
;;; luks-device-mapping.
;;;
;;; State: tested in QEMU, not yet on the phone (screen, keyboard, UFS timing).

(define-module (fxtec-pro1x services fde)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system linux-initrd)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (ice-9 match)
  #:autoload   (gnu packages cryptsetup) (cryptsetup-static)
  #:autoload   (fxtec-pro1x packages misc) (pro1x-loop-offset)
  #:export (%pro1x-boot-area-mib
            %pro1x-fde-mapped-devices
            %pro1x-fde-file-systems
            pro1x-fde-initrd
            pro1x-fde-prompt-test-initrd
            luks-pro1x-device-mapping))

(define %pro1x-boot-area-mib 512)

;; CONFIG_BLK_DEV_LOOP=y, CONFIG_BLK_DEV_LOOP_MIN_COUNT=8: it exists at boot,
;; and nothing else uses a loop device in the initrd.
(define %pro1x-luks-loop "/dev/loop0")

;; Guix's own LUKS mapping, as on any Guix system, opening the loop device; only
;; the step before it is the port's.  SOURCE is the name of the partition holding
;; the container.
(define* (open-luks-pro1x source targets . options)
  #~(let ((part-name #$source))
      ;; udev's /dev/disk/by-partlabel is not there yet; the kernel gives the
      ;; name in each partition's uevent.
      (define (partition-device)
        (any (lambda (name)
               (let ((uevent (string-append "/sys/class/block/" name "/uevent")))
                 (and (file-exists? uevent)
                      (string-contains
                       (call-with-input-file uevent get-string-all)
                       (string-append "PARTNAME=" part-name "\n"))
                      (string-append "/dev/" name))))
             (or (scandir "/sys/class/block") '())))

      ;; Storage probes in parallel with the initrd.
      (define (wait-for-partition seconds)
        (or (partition-device)
            (and (> seconds 0)
                 (begin (sleep 1) (wait-for-partition (- seconds 1))))))

      (let ((device (wait-for-partition 60)))
        (unless device
          (format #t "partition ~a not found~%" part-name))
        (and device
             (zero? (system* #$(file-append pro1x-loop-offset
                                            "/bin/pro1x-loop-offset")
                             #$%pro1x-luks-loop device
                             #$(number->string
                                (* %pro1x-boot-area-mib 1024 1024))))
             #$(apply (mapped-device-kind-open luks-device-mapping)
                      %pro1x-luks-loop targets options)))))

(define luks-pro1x-device-mapping
  (mapped-device-kind
   (inherit luks-device-mapping)
   (open open-luks-pro1x)
   ;; Its modules include (rnrs io ports), for get-string-all.
   (modules (cons '(ice-9 ftw)          ; scandir
                  (mapped-device-kind-modules luks-device-mapping)))))

(define %pro1x-fde-mapped-devices
  (list
   (mapped-device
    (source "userdata")
    (targets '("pro1x-crypt"))
    (type luks-pro1x-device-mapping)
    ;; Failing leads to a Guile REPL, of no use here, so as good as ask until it
    ;; is right.  Not 0, unlimited in the manual: cryptsetup 2.8 aborts on it
    ;; (luks_try_token_unlock: Assertion `tries >= 1').
    (arguments '(#:extra-options ("--tries" "1000000"))))))

(define %pro1x-fde-file-systems
  (list
   ;; Hides nothing the system needs, and a system that cannot mount it still
   ;; runs: only the boot menu's updates depend on it.
   (file-system
     (device (file-system-label "guixboot"))
     (mount-point "/boot")
     (type "ext4")
     (check? #f)
     (mount-may-fail? #t)
     (create-mount-point? #t)
     (flags '(no-atime)))
   (file-system
     (device (file-system-label "guix"))
     (mount-point "/")
     (type "ext4")
     (flags '(no-atime)))))

(define (pro1x-fde-initrd devices)
  "Return an initrd procedure for an operating-system that always opens DEVICES.
The initrd is the only place that does: they are not in the system's
mapped-devices, nor dependencies of its root.  `guix system image' replaces the
root file system with one without dependencies (operating-system-for-image), so
Guix would leave them out of the image's initrd, and take them for devices to
open from Shepherd, whose configuration then failed to load (seen in QEMU)."
  (lambda (file-systems . rest)
    ;; The last occurrence of a keyword wins.
    (apply base-initrd file-systems
           (append rest (list #:mapped-devices devices)))))

;;; The prompt on the phone, without wiping it: a generation whose initrd, on the
;;; unencrypted system, asks for the passphrases of two small LUKS2 files in
;;; /var/lib/pro1x/ (same Argon2 cost as flash-encrypted.sh), then boots as usual
;;; whatever happened.  Two: one for the letters, one for the digits, to tell which
;;; part of the keyboard fails.  Results are in dmesg ("pro1x-fde-test").  Made by
;;; PRO1X_FDE_PROMPT_TEST=1 scripts/deploy.sh; the next deploy without it removes
;;; it.  What this shows on the screen and keyboard holds for the real prompt, which
;;; is the same cryptsetup on the same console.
(define (open-fde-prompt-test source targets . options)
  #~(let ((cryptsetup #$(file-append cryptsetup-static "/sbin/cryptsetup"))
          (mnt "/fde-test"))
      (define (partition-device)
        (any (lambda (name)
               (let ((uevent (string-append "/sys/class/block/" name "/uevent")))
                 (and (file-exists? uevent)
                      (string-contains
                       (call-with-input-file uevent get-string-all)
                       (string-append "PARTNAME=" #$source "\n"))
                      (string-append "/dev/" name))))
             (or (scandir "/sys/class/block") '())))

      (define (wait-for-partition seconds)
        (or (partition-device)
            (and (> seconds 0)
                 (begin (sleep 1) (wait-for-partition (- seconds 1))))))

      (define (log message)
        (call-with-output-file "/dev/kmsg"
          (lambda (port)
            (format port "pro1x-fde-test: ~a~%" message))))

      (define (try name)
        (let* ((start (current-time))
               (file (string-append mnt "/var/lib/pro1x/fde-test-" name ".luks"))
               (code (status:exit-val
                      (system*/tty cryptsetup "open" "--type" "luks2" "--readonly"
                                   "--tries" "3" "--timeout" "120"
                                   file (string-append "fde-test-" name)))))
          (log (format #f "~a: cryptsetup exit ~a after ~a s"
                       name code (- (current-time) start)))
          (when (zero? code)
            (system* cryptsetup "close" (string-append "fde-test-" name)))))

      (mkdir-p "/run/cryptsetup/")
      (mkdir-p mnt)
      (log "started")
      (let ((device (wait-for-partition 60)))
        (log (format #f "partition: ~a" device))
        (when device
          (false-if-exception
           ((@ (guix build syscalls) mount) device mnt "ext4"
            (@ (guix build syscalls) MS_RDONLY)))
          (format #t "~%KEYBOARD TEST.  Open the keyboard.  Letters, top row first:~%")
          (try "letters")
          (format #t "~%KEYBOARD TEST.  Digits, 1 to 0:~%")
          (try "digits")
          (false-if-exception ((@ (guix build syscalls) umount) mnt))))
      ;; Whatever came of it, the system boots.
      #t))

(define pro1x-fde-prompt-test-mapping
  (mapped-device-kind
   (inherit luks-device-mapping)
   (open open-fde-prompt-test)
   (modules (cons '(ice-9 ftw) (mapped-device-kind-modules luks-device-mapping)))))

(define (pro1x-fde-prompt-test-initrd)
  "Return the initrd procedure of the test above."
  (pro1x-fde-initrd
   (list (mapped-device
          (source "userdata")
          (targets '("pro1x-fde-test"))
          (type pro1x-fde-prompt-test-mapping)))))
