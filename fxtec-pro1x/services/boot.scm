;;; fxtec-pro1x/services/boot.scm — boot menu split + boot-slot success marking
;;; Translates modules/boot-menu.nix and modules/boot-success.nix.

(define-module (fxtec-pro1x services boot)
  #:use-module (fxtec-pro1x packages misc)   ; qbootctl
  #:use-module (gnu packages base)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages linux)          ; e2fsprogs
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
  (generations pro1x-boot-menu-generations (default 3)))

;;; The split script: mirrors modules/boot-menu.nix's `split`.
(define (pro1x-boot-menu-split-script config)
  (let ((n (pro1x-boot-menu-generations config)))
    (computed-file "pro1x-boot-menu-split"
      #~(call-with-output-file #$output
          (lambda (port)
            (display "#!/bin/sh\nset -eu\n" port)
            (display "dir=/boot/extlinux\n" port)
            (display "src=$dir/extlinux.conf\n" port)
            (display "[ -f \"$src\" ] || exit 0\n" port)
            (display (string-append "for n in $(seq 1 " #$(number->string n) "); do\n") port)
            (display (string-append
                      "  " #$gawk "/bin/awk -v want=$((n + 2)) '\n"
                      "    /^[[:space:]]*LABEL[[:space:]]/ { entry++; if (entry == want) label = $2 }\n"
                      "    entry == want { body = body $0 \"\\n\" }\n"
                      "    END {\n"
                      "      if (body == \"\") exit 1\n"
                      "      print \"TIMEOUT 0\"\n"
                      "      print \"PROMPT 0\"\n"
                      "      print \"DEFAULT \" label\n"
                      "      printf \"%s\", body\n"
                      "    }\n"
                      "  ' \"$src\" > \"$dir/.prev$n.tmp\" \\\n"
                      "    || { rm -f \"$dir/.prev$n.tmp\" \"$dir/prev$n.conf\"; continue; }\n"
                      "  mv -f \"$dir/.prev$n.tmp\" \"$dir/prev$n.conf\"\n"
                      "done\n")
                     port)
            (display "for f in $dir/prev*.conf; do\n" port)
            (display "  [ -e \"$f\" ] || continue\n" port)
            (display "  nn=${f##*/prev}; nn=${nn%.conf}\n" port)
            (display (string-append "  [ \"$nn\" -le " #$(number->string n) " ] || rm -f \"$f\"\n") port)
            (display "done\n" port)
            (chmod #$output #o755))))))

(define (pro1x-boot-menu-shepherd-services config)
  (if (> (pro1x-boot-menu-generations config) 0)
      (let ((split (pro1x-boot-menu-split-script config)))
        (list
         (shepherd-service
          (provision '(pro1x-boot-menu))
          (requirement '(file-systems))
          (documentation "Write /boot/extlinux/prev*.conf for the U-Boot menu")
          (one-shot? #t)
          (start
           #~(make-forkexec-constructor
              (list #$split)
              #:log-file "/var/log/pro1x-boot-menu.log"))
          (stop #~(make-kill-destructor)))))
      '()))

(define pro1x-boot-menu-service-type
  (service-type
   (name 'pro1x-boot-menu)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-boot-menu-shepherd-services)))
   (default-value (pro1x-boot-menu-configuration))
   (description "Write /boot/extlinux/prev1.conf … prevN.conf so the U-Boot
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
    (documentation "Expand the root ext4 filesystem to fill its partition (runs once)")
    (one-shot? #t)
    (start
     #~(make-forkexec-constructor
        (list "/bin/sh" "-c"
              (string-append
               "[ -f /var/lib/pro1x-rootfs-resized ] && exit 0; "
               "dev=$(awk '$2==\"/\" {print $1; exit}' /proc/mounts) && "
               #$(file-append e2fsprogs "/sbin/resize2fs") " \"$dev\" && "
               "touch /var/lib/pro1x-rootfs-resized"))
        #:log-file "/var/log/pro1x-rootfs-resize.log"))
    (stop #~(make-kill-destructor)))))

(define pro1x-rootfs-resize-service-type
  (service-type
   (name 'pro1x-rootfs-resize)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-rootfs-resize-shepherd-services)))
   (default-value #f)
   (description "Expand the root ext4 filesystem to fill its partition once
after flashing.  A flag file /var/lib/pro1x-rootfs-resized is created on
success so the resize is never attempted again.")))
