;;; fxtec-pro1x/services/fde.scm — offset LUKS2 mapped-device for the Pro1X
;;;
;;; The userdata partition is laid out as:
;;;   [0, 256 MiB)  : plain ext4 labelled "guixboot" (kernel, initrd,
;;;                   extlinux.conf; readable by U-Boot without decryption)
;;;   [256 MiB, …)  : LUKS2 container (header + encrypted root ext4)
;;;
;;; luks-pro1x-device-mapping opens the LUKS2 header at offset 256 MiB within
;;; /dev/disk/by-partlabel/userdata, exposed as /dev/mapper/pro1x-crypt.
;;; A loop device (/dev/loop0) is used because 'cryptsetup open' for LUKS2
;;; does not support --offset (that flag is for plain/loop-AES only).
;;; CONFIG_BLK_DEV_LOOP=y in the Pro1X kernel; /dev/loop0 exists at boot.

(define-module (fxtec-pro1x services fde)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (ice-9 match)
  #:autoload   (gnu packages cryptsetup) (cryptsetup-static)
  #:export (%pro1x-luks-offset-sectors
            luks-pro1x-device-mapping))

;; 256 MiB plain boot area before the LUKS2 header (256 * 2048 sectors).
(define %pro1x-luks-offset-sectors (* 256 2048))  ; = 524288

;; /dev/loop0 is pre-created by the kernel (CONFIG_BLK_DEV_LOOP=y,
;; CONFIG_BLK_DEV_LOOP_MIN_COUNT=8).  Reserved here; no competing uses in initrd.
(define %pro1x-luks-loop "/dev/loop0")

(define (open-luks-pro1x source targets)
  (match targets
    ((target)
     (with-imported-modules (source-module-closure
                             '((gnu build file-systems)
                               (guix build utils)))
       #~(begin
           (use-modules ((gnu build file-systems) #:select (system*/tty))
                        ((guix build utils) #:select (mkdir-p)))
           (mkdir-p "/run/cryptsetup/")
           ;; Expose the LUKS region via a loop device (cryptsetup open for
           ;; LUKS2 does not support --offset; that flag is plain/loop-AES only).
           (and (zero? (system* "losetup"
                                "-o"
                                #$(number->string (* %pro1x-luks-offset-sectors 512))
                                #$%pro1x-luks-loop
                                #$source))
                (zero? (system*/tty
                        #$(file-append cryptsetup-static "/sbin/cryptsetup")
                        "open" "--type" "luks2"
                        #$%pro1x-luks-loop #$target))))))))

(define (close-luks-pro1x source targets)
  (match targets
    ((target)
     (with-imported-modules (source-module-closure '((guix build utils)))
       #~(begin
           (use-modules ((guix build utils) #:select (system*)))
           (and (zero? (system*
                        #$(file-append cryptsetup-static "/sbin/cryptsetup")
                        "close" #$target))
                (zero? (system* "losetup" "-d" #$%pro1x-luks-loop))))))))

(define luks-pro1x-device-mapping
  (mapped-device-kind
   (open  open-luks-pro1x)
   (close close-luks-pro1x)))
