;;; fxtec-pro1x/services/modem.scm — tqftpserv + rmtfs + ModemManager
;;; Translates modules/modem.nix.

(define-module (fxtec-pro1x services modem)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages telephony)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services dbus)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-modem-configuration
            pro1x-modem-configuration?
            make-pro1x-modem-configuration
            pro1x-modem-service-type))

(define-record-type* <pro1x-modem-configuration>
  pro1x-modem-configuration make-pro1x-modem-configuration
  pro1x-modem-configuration?
  (verbose? pro1x-modem-verbose? (default #f)))

(define (pro1x-modem-shepherd-services config)
  (let ((verbose-flag (if (pro1x-modem-verbose? config) '("-v") '())))
    (list

     ;; tqftpserv: deliver modem firmware over QRTR.
     ;; The binary is patched to look for firmware at /run/current-system/firmware.
     ;; Guix's activate-firmware sets firmware_class.path in sysfs but does not
     ;; create that symlink; we create it here at service-start time, after the
     ;; activation scripts have already run.
     (shepherd-service
      (provision '(tqftpserv))
      (requirement '(udev))
      (documentation "TFTP server for Qualcomm modem firmware (QRTR)")
      (start
       #~(make-forkexec-constructor
          (list "/bin/sh" "-c"
                (string-append
                 "fw=$(cat /sys/module/firmware_class/parameters/path 2>/dev/null);"
                 "[ -n \"$fw\" ] && [ ! -e /run/current-system/firmware ]"
                 " && ln -sf \"$fw\" /run/current-system/firmware;"
                 "exec " #$(file-append tqftpserv "/bin/tqftpserv")
                 #$(if (pro1x-modem-verbose? config) " -v" "")))
          #:log-file "/var/log/tqftpserv.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t))

     ;; rmtfs: wait for modem remoteproc, then serve EFS partitions
     (shepherd-service
      (provision '(rmtfs))
      (requirement '(udev tqftpserv pro1x-modem-ready))
      (documentation "Qualcomm remote filesystem service (modemst1/2, fsg, fsc)")
      (start
       #~(make-forkexec-constructor
          ;; ExecStartPre: wait up to 180 s for modem remoteproc
          (append (list #$(file-append rmtfs "/bin/rmtfs")
                        "-r" "-P" "-s")
                  '#$verbose-flag)
          #:environment-variables
          '("PATH=/run/current-system/profile/bin")
          #:log-file "/var/log/rmtfs.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t))

     ;; ModemManager: the high-level modem manager
     (shepherd-service
      (provision '(modem-manager))
      (requirement '(dbus-system tqftpserv rmtfs))
      (documentation "ModemManager")
      (start
       #~(make-forkexec-constructor
          (list #$(file-append modem-manager "/sbin/ModemManager"))
          #:log-file "/var/log/ModemManager.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t)))))

;;; A one-shot service that blocks rmtfs startup until the modem remoteproc appears.
(define (pro1x-modem-rmtfs-wait config)
  (list
   (shepherd-service
    (provision '(pro1x-modem-ready))
    (requirement '(udev))
    (documentation "Wait for modem remoteproc before starting rmtfs")
    (one-shot? #t)
    (start
     #~(make-forkexec-constructor
        (list #$(computed-file "rmtfs-wait"
                  #~(begin
                      (call-with-output-file #$output
                        (lambda (port)
                          (display "#!/bin/sh\n" port)
                          (display "i=0\n" port)
                          (display "while [ \"$i\" -lt 180 ]; do\n" port)
                          (display "  for n in /sys/class/remoteproc/*/name; do\n" port)
                          (display "    [ -r \"$n\" ] && [ \"$(cat \"$n\")\" = modem ] && exit 0\n" port)
                          (display "  done\n" port)
                          (display "  i=$((i+1)); sleep 1\n" port)
                          (display "done\n" port)
                          (display "echo 'modem remoteproc not found' >&2; exit 1\n" port)))
                      (chmod #$output #o755))))
        #:log-file "/var/log/pro1x-modem-wait.log"))
    (stop #~(make-kill-destructor)))))

(define (pro1x-modem-packages config)
  (list tqftpserv rmtfs modem-manager))

(define pro1x-modem-service-type
  (service-type
   (name 'pro1x-modem)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        (lambda (config)
                          (append (pro1x-modem-rmtfs-wait config)
                                  (pro1x-modem-shepherd-services config))))
     (service-extension dbus-root-service-type
                        (lambda (_) (list modem-manager)))
     (service-extension profile-service-type
                        pro1x-modem-packages)))
   (default-value (pro1x-modem-configuration))
   (description "Qualcomm modem userspace for the Pro1X: tqftpserv (firmware),
rmtfs (EFS partitions), and ModemManager.  Wi-Fi firmware also goes through
tqftpserv, so enable this service even without a SIM.")))
