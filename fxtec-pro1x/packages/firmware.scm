;;; fxtec-pro1x/packages/firmware.scm — proprietary firmware for the QX1050

(define-module (fxtec-pro1x packages firmware)
  #:use-module (guix build-system copy)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (firmware-fxtec-qx1050))

(define-public firmware-fxtec-qx1050
  (package
    (name "firmware-fxtec-qx1050")
    (version "unstable-6c1ef5b")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/sm6115-mainline/firmware-fxtec-qx1050"
             "/archive/6c1ef5bce85750688f789bc6e232ca8237b24713.tar.gz"))
       (sha256
        (base32 "1cgi0p9h2iaivgydn8hw4jzp2x42rhc79rvn74lh1xrnr1p362fn"))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("lib" "lib"))
           #:validate-runpath? #f))
    (home-page "https://github.com/sm6115-mainline/firmware-fxtec-qx1050")
    (synopsis "Proprietary firmware for the F(x)tec Pro1X (QX1050)")
    (description
     "Qualcomm firmware blobs for the F(x)tec Pro1X (SM6115): GPU (a610), Wi-Fi
(ath10k), Bluetooth (qca), modem remoteproc images, and sensor DSP firmware.
These live under lib/firmware/qcom/sm6115/Fxtec/QX1050/ matching the DTS path.")
    ;; Qualcomm proprietary — users must accept their own terms.
    (license (license:non-copyleft
              "https://github.com/sm6115-mainline/firmware-fxtec-qx1050/blob/main/LICENSE"
              "Qualcomm proprietary firmware"))))
