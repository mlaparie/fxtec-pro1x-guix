;;; fxtec-pro1x/services/fingerprint.scm — the fingerprint trusted app's services
;;;
;;; The sensor runs inside a QSEE trusted app, mafp (device/fingerprint/
;;; README.md).  The kernel's QSEECOM TEE driver (patch pro1x-qseecom-tee,
;;; module qseecomtee) loads it and carries its commands; qsee-supplicant
;;; answers the app's file system listener requests (its templates live
;;; under /var/lib/qsee-supplicant); qsee-app-loader keeps mafp loaded.
;;;
;;; Neither service starts at boot (autostart? #f) until loading the app
;;; has been tried by hand on this kernel: herd start qsee-app-loader-mafp.
;;;
;;; State: build-tested only.

(define-module (fxtec-pro1x services fingerprint)
  #:use-module (fxtec-pro1x packages fingerprint)
  #:use-module (gnu packages linux)         ; kmod
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-fingerprint-configuration
            pro1x-fingerprint-configuration?
            pro1x-fingerprint-service-type))

(define-record-type* <pro1x-fingerprint-configuration>
  pro1x-fingerprint-configuration make-pro1x-fingerprint-configuration
  pro1x-fingerprint-configuration?
  ;; Start the supplicant and load mafp at boot?
  (autostart? pro1x-fingerprint-autostart? (default #f)))

(define (pro1x-fingerprint-shepherd-services config)
  (let ((autostart? (pro1x-fingerprint-autostart? config)))
    (list
     (shepherd-service
      (provision '(qsee-supplicant))
      (requirement '(udev))
      (documentation "Answer QSEE trusted apps' listener requests")
      (auto-start? autostart?)
      (start
       #~(lambda _
           ;; The driver's device comes from qcom_scm; load the module in
           ;; case udev has not.
           (system* #$(file-append kmod "/bin/modprobe") "qseecomtee")
           (fork+exec-command
            (list #$(file-append qsee-supplicant "/sbin/qsee-supplicant")
                  "--state-dir" "/var/lib/qsee-supplicant")
            #:log-file "/var/log/qsee-supplicant.log")))
      (stop #~(make-kill-destructor))
      (respawn? #f))
     (shepherd-service
      (provision '(qsee-app-loader-mafp))
      (requirement '(qsee-supplicant))
      (documentation "Keep the fingerprint trusted app, mafp, loaded")
      (auto-start? autostart?)
      (start
       #~(make-forkexec-constructor
          (list #$(file-append qsee-supplicant "/sbin/qsee-app-loader")
                "mafp")
          #:log-file "/var/log/qsee-app-loader-mafp.log"))
      (stop #~(make-kill-destructor))
      (respawn? #f)))))

(define pro1x-fingerprint-service-type
  (service-type
   (name 'pro1x-fingerprint)
   (extensions
    (list (service-extension shepherd-root-service-type
                             pro1x-fingerprint-shepherd-services)
          (service-extension profile-service-type
                             (const (list qsee-supplicant)))))
   (default-value (pro1x-fingerprint-configuration))
   (description "Services for the Pro1X's fingerprint trusted app.")))
