;;; fxtec-pro1x/packages/power-tools.scm — measuring the phone's power draw
;;;
;;; Debug modules, not in the system: build, then insmod by hand.
;;;   guix build --system=aarch64-linux -L modules pro1x-qgsleep

(define-module (fxtec-pro1x packages power-tools)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages kernel)
  #:use-module (guix build-system linux-module)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:))

;;; moWerk's sleep-current probe (device/power/qgsleep/README.md).
;;; State: build-tested only.
(define-public pro1x-qgsleep
  (package
    (name "pro1x-qgsleep")
    (version "0.1")
    (source (local-file (repository-file "device/power/qgsleep")
                        "pro1x-qgsleep"
                        #:recursive? #t))
    (build-system linux-module-build-system)
    (arguments
     (list #:linux linux-pro1x
           #:tests? #f))
    (supported-systems '("aarch64-linux"))
    (home-page "https://github.com/moWerk/sailfishos-pro1x-mainline")
    (synopsis "Print the Pro1X battery current of each system sleep")
    (description
     "A Linux module that restarts the PMI632 fuel gauge's sample FIFO at
suspend and prints its mean current at resume: the battery current while the
phone slept.  For measurements only.")
    (license license:gpl2)))
