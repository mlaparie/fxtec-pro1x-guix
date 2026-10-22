;;; fxtec-pro1x/packages/firmware.scm — proprietary firmware for the QX1050

(define-module (fxtec-pro1x packages firmware)
  #:use-module (guix build-system copy)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (firmware-fxtec-qx1050))

(define-public firmware-fxtec-qx1050
  (package
    (name "firmware-fxtec-qx1050")
    (version "unstable-6c1ef5b")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/sm6115-mainline/firmware-fxtec-qx1050")
             (commit "6c1ef5bce85750688f789bc6e232ca8237b24713")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0000000000000000000000000000000000000000000000000000"))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("lib" "lib"))))
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
