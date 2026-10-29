;;; fxtec-pro1x/packages/kernel.scm — Linux 7.1 for the F(x)tec Pro1X (SM6115)
;;;
;;; The source is the sm6115-mainline tree (not linux-libre).  Build infra-
;;; structure is borrowed from the nonguix `linux` package so we skip deblob-
;;; bing.  To get the sha256 after the first attempt:
;;;   guix build --system=aarch64-linux linux-pro1x -L modules
;;; Guix will print the expected hash on failure.

(define-module (fxtec-pro1x packages kernel)
  #:use-module (gnu packages linux)
  #:use-module (nongnu packages linux)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (linux-pro1x))

;;; The 14 device patches, applied in the same order as the NixOS port.
(define %pro1x-patch-dir
  (string-append (current-source-directory) "/../../../device/kernel/patches/"))

(define %pro1x-patches
  (map (lambda (n)
         (local-file (string-append %pro1x-patch-dir "pro1x-" n ".patch")
                     (string-append "pro1x-" n ".patch")))
       '("touch"
         "egpio"
         "dsi"
         "panelgap"
         "dpugap"
         "audio"
         "q6voice"
         "camera"
         "keyboard"
         "leds"
         "power"
         "haptics"
         "bluetooth"
         "ipa")))

(define-public linux-pro1x
  (package
    (inherit linux)                           ; nonguix `linux`, no deblob
    (name "linux-pro1x")
    (version "7.1.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/sm6115-mainline/linux/archive/"
             "8cd9520d35a6c38db6567e97dd93b1f11f185dc6.tar.gz"))
       (sha256
        (base32 "0m8fffprbm32y28h878hdvwfi8y0v5xm5vylz9zmmxlclqp9b29v"))
       (patches %pro1x-patches)))
    (supported-systems '("aarch64-linux"))
    (arguments
     (substitute-keyword-arguments (package-arguments linux)
       ((#:make-flags _)
        #~(list "ARCH=arm64"
                "CROSS_COMPILE=aarch64-linux-gnu-"))
       ((#:phases phases)
        #~(modify-phases #$phases
            (add-after 'unpack 'fix-hardcoded-bin-sh
              (lambda _
                (substitute* "arch/arm64/tools/Makefile"
                  (("/bin/sh") "sh"))))

            (replace 'configure
              (lambda _
                (copy-file
                 #$(local-file (string-append (current-source-directory)
                                              "/../../../device/kernel/config.aarch64")
                               "pro1x.config")
                 ".config")
                (invoke "make" "ARCH=arm64" "olddefconfig")))))))
    (synopsis "Linux kernel for the F(x)tec Pro1X (QX1050 / SM6115)")
    (description
     "Mainline Linux 7.1 from the sm6115-mainline tree, with device patches
for the F(x)tec Pro1X: AW9523B keyboard matrix, BOE DSI panel (60 Hz),
Goodix GT9286 touch, WCN3950 Bluetooth, AW86224 haptics, q6voice DSP bridge,
IMX582/DW9800 rear camera, S5K4H7 front camera, LED controllers, PM and more.")
    (license license:gpl2)))
