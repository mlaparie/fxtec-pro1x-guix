;;; fxtec-pro1x/packages/fingerprint.scm — fingerprint reader experiments
;;;
;;; The sensor runs inside a QSEE trusted app (device/fingerprint/README.md).
;;; Nothing here is in the system yet: build the module and insmod it by
;;; hand on the phone.
;;;   guix build --system=aarch64-linux -L modules pro1x-qsee-probe

(define-module (fxtec-pro1x packages fingerprint)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages kernel)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system linux-module)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils)
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

;;; The listener side of the QSEECOM TEE driver (kernel patch
;;; pro1x-qseecom-tee): a trusted app asks Linux to read and write its files
;;; through listener services, and this daemon answers the File System and
;;; GlobalPlatform File System listeners, keeping the files under
;;; /var/lib/qsee-supplicant.  qsee-app-loader keeps one named app loaded.
;;; By Dawid Wróbel, BSD-2-Clause.
;;; State: build-tested only.
(define-public qsee-supplicant
  (let ((commit "36e06680cf7f690fccbdcd07abc2a64c4bb061d8")
        (revision "1"))
    (package
      (name "qsee-supplicant")
      (version (git-version "0.1.1" revision commit))
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/wrobelda/qsee-supplicant")
               (commit commit)))
         (file-name (git-file-name name version))
         (sha256
          (base32 "1bzkmxxdvm9mfb7i439b8639q9cnf2amwhsqdfv2vf1v5bgcwsah"))))
      (build-system gnu-build-system)
      (arguments
       (list #:make-flags
             #~(list (string-append "CC=" #$(cc-for-target))
                     (string-append "PREFIX=" #$output))
             #:test-target "check"
             #:phases
             #~(modify-phases %standard-phases
                 (delete 'configure)
                 ;; The programs and the README; no systemd or OpenRC units.
                 (replace 'install
                   (lambda* (#:key make-flags #:allow-other-keys)
                     (apply invoke "make" "install-bin" "install-doc"
                            make-flags))))))
      (home-page "https://github.com/wrobelda/qsee-supplicant")
      (synopsis "Listener services and app loader for Qualcomm QSEE")
      (description
       "qsee-supplicant answers the file system listener requests of
Qualcomm QSEE trusted applications through the Linux QSEECOM TEE driver, and
qsee-app-loader keeps a named trusted application loaded.")
      (license license:bsd-2))))

;;; The fingerprint trusted app, mafp, as one signed image (the QSEECOM TEE
;;; driver loads <name>.mbn when there is no <name>.mdt, with an .mdt length
;;; of zero).  From the LineageOS vendor blobs, pinned; byte-identical to the
;;; file analysed in device/fingerprint/README.md.  Proprietary.
;;; State: build-tested only.
(define-public firmware-fxtec-qx1050-mafp
  (let ((commit "ea4f9ed909f932b3b5f1322bf8605c222313a444"))
    (package
      (name "firmware-fxtec-qx1050-mafp")
      (version (string-append "lineage-21-" (string-take commit 7)))
      (source
       (origin
         (method url-fetch)
         (uri (string-append
               "https://raw.githubusercontent.com/TheMuppets/"
               "proprietary_vendor_fxtec_pro1x/" commit
               "/proprietary/vendor/firmware/mafp.mbn"))
         (sha256
          (base32 "1bkh8v4bi9n1q6hzsjgzc7awx4d5n94f90i5dgc27klqzk7cg5wm"))))
      (build-system copy-build-system)
      (arguments
       (list #:install-plan #~'(("mafp.mbn" "lib/firmware/"))
             #:validate-runpath? #f))       ;an ELF, but not for Linux
      (home-page "https://github.com/TheMuppets/proprietary_vendor_fxtec_pro1x")
      (synopsis "Fingerprint trusted app of the F(x)tec Pro1X (proprietary)")
      (description
       "The MicroArray fingerprint trusted application (mafp) that runs in
Qualcomm QSEE on the F(x)tec Pro1X.")
      (license (license:non-copyleft
                "https://github.com/TheMuppets/proprietary_vendor_fxtec_pro1x"
                "Proprietary firmware")))))

;;; mafp-client: sends one command to the fingerprint trusted app through the
;;; QSEECOM TEE driver and prints the reply (device/fingerprint/mafp-client).
;;; A test tool for mapping the protocol.
;;; State: build-tested only.
(define-public mafp-client
  (package
    (name "mafp-client")
    (version "0.1")
    (source (local-file (repository-file "device/fingerprint/mafp-client")
                        "mafp-client"
                        #:recursive? #t))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f
           #:phases
           #~(modify-phases %standard-phases
               (delete 'configure)
               (replace 'build
                 (lambda _
                   (invoke #$(cc-for-target) "-O2" "-Wall" "-Wextra"
                           "-o" "mafp-client" "mafp-client.c")))
               (replace 'install
                 (lambda _
                   (install-file "mafp-client"
                                 (string-append #$output "/bin")))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Send a command to the Pro1X fingerprint trusted app")
    (description
     "A test tool: sends one command to the MicroArray fingerprint trusted
application (mafp) through the Linux QSEECOM TEE driver and prints the reply.")
    (license license:gpl3+)))
