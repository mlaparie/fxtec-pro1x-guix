;;; fxtec-pro1x/services/fde.scm — offset LUKS2 mapped-device for the Pro1X
;;;
;;; The userdata partition is laid out as:
;;;   [0, 256 MiB)  : plain ext4 labelled "guixboot" (kernel, initrd,
;;;                   extlinux.conf; readable by U-Boot without decryption)
;;;   [256 MiB, …)  : LUKS2 container (header + encrypted root ext4)
;;;
;;; luks-pro1x-device-mapping opens the LUKS2 header at offset
;;; %pro1x-luks-offset-sectors (= 256 MiB) within /dev/disk/by-partlabel/userdata
;;; and exposes it as /dev/mapper/pro1x-crypt.

(define-module (fxtec-pro1x services fde)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (ice-9 match)
  #:autoload   (gnu packages cryptsetup) (cryptsetup-static)
  #:export (%pro1x-luks-offset-sectors
            luks-pro1x-device-mapping))

;; 256 MiB plain boot area before the LUKS2 header (256 * 2048 sectors).
(define %pro1x-luks-offset-sectors (* 256 2048))

(define (open-luks-pro1x source targets)
  (match targets
    ((target)
     (with-imported-modules (source-module-closure
                             '((gnu build file-systems)
                               (guix build utils)))
       #~(begin
           (use-modules ((gnu build file-systems) #:select (system*/tty))
                        ((guix build utils) #:select (mkdir-p)))
           ;; LUKS2 device locking requires /run/cryptsetup/ to exist.
           (mkdir-p "/run/cryptsetup/")
           (zero? (system*/tty
                   #$(file-append cryptsetup-static "/sbin/cryptsetup")
                   "open" "--type" "luks2"
                   "--offset"
                   #$(number->string %pro1x-luks-offset-sectors)
                   #$source #$target)))))))

(define (close-luks-pro1x source targets)
  (match targets
    ((target)
     #~(zero? (system*
               #$(file-append cryptsetup-static "/sbin/cryptsetup")
               "close" #$target)))))

(define luks-pro1x-device-mapping
  (mapped-device-kind
   (open  open-luks-pro1x)
   (close close-luks-pro1x)))
