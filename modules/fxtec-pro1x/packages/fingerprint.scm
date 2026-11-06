;;; fxtec-pro1x/packages/fingerprint.scm — fingerprint reader experiments
;;;
;;; The sensor runs inside a QSEE trusted app (device/fingerprint/README.md).
;;; Nothing here is in the system yet: build the module and insmod it by
;;; hand on the phone.
;;;   guix build --system=aarch64-linux -L modules pro1x-qsee-probe

(define-module (fxtec-pro1x packages fingerprint)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages kernel)
  #:use-module (guix build-system linux-module)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:))

;;; A test module: looks up QSEE apps, loads the stock mafp TA and sends it
;;; one command, all chosen by module parameters (see the source).
;;; State: build-tested only.
(define-public pro1x-qsee-probe
  (package
    (name "pro1x-qsee-probe")
    (version "0.1")
    (source (local-file (repository-file "device/fingerprint/qsee-probe")
                        "pro1x-qsee-probe"
                        #:recursive? #t))
    (build-system linux-module-build-system)
    (arguments
     (list #:linux linux-pro1x
           #:tests? #f))
    (supported-systems '("aarch64-linux"))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Probe the Pro1X fingerprint trusted app under mainline QSEECOM")
    (description
     "A Linux module that looks up QSEE apps, can load the stock MicroArray
fingerprint trusted app (mafp) with the QSEE OS app-start call that mainline
lacks, and send it one command.  For experiments only.")
    (license license:gpl2)))
