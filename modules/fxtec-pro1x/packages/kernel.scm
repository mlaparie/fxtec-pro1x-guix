;;; fxtec-pro1x/packages/kernel.scm — Linux 7.1 for the F(x)tec Pro1X (SM6115)
;;;
;;; The source is the sm6115-mainline tree (not linux-libre).  Build infra-
;;; structure is borrowed from the nonguix `linux` package so we skip deblob-
;;; bing.  To get the sha256 after the first attempt:
;;;   guix build --system=aarch64-linux linux-pro1x -L modules
;;; Guix will print the expected hash on failure.

(define-module (fxtec-pro1x packages kernel)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages linux)
  #:use-module (nongnu packages linux)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (ice-9 ftw)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (linux-pro1x))

;;; The device patches: the NixOS port's 14, in its order, then ours.
(define %pro1x-patch-dir
  (repository-file "device/kernel/patches/"))

(define %pro1x-7.3-patch-dir
  (repository-file "device/kernel/patches-7.3/"))

(define %pro1x-patches
  ;; Kernel 7.3 (branch kernel-7.3): moWerk's series, in file-name order
  ;; (device/kernel/patches-7.3/README.md: origin, what is left out), then
  ;; ours.
  (append
   (map (lambda (f)
          (local-file (string-append %pro1x-7.3-patch-dir f) f))
        (scandir %pro1x-7.3-patch-dir
                 (lambda (f) (string-suffix? ".patch" f))))
   (map (lambda (n)
          (local-file (string-append %pro1x-patch-dir "pro1x-" n ".patch")
                      (string-append "pro1x-" n ".patch")))
        ;; Ours: panel and DPU gaps (NixOS port, module parameters, off by
        ;; default); the modem's QRTR data for user space wakes a suspended
        ;; system, only from the listed ports (v4; pro1x-sleep lists voice
        ;; and SMS).
        '("panelgap" "dpugap" "qrtr-modem-wake"))))

(define-public linux-pro1x
  (package
    (inherit linux)                           ; nonguix `linux`, no deblob
    (name "linux-pro1x")
    (version "7.3.0")
    (source
     (origin
       (method url-fetch)
       ;; Mainline v7.3, as moWerk's series expects.
       (uri "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz")
       (sha256
        (base32 "0ls902gz6h1ydcnwx2zzdcglg52f14hmaxk2ncg341hfy4j3qdl7"))
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
                 #$(local-file (repository-file "device/kernel/config.aarch64")
                               "pro1x.config")
                 ".config")
                ;; What the 7.3 series needs on top (pro1x-7.3.fragment).
                (invoke "sh" "-c"
                        (string-append
                         "cat "
                         #$(local-file (repository-file
                                        "device/kernel/pro1x-7.3.fragment")
                                       "pro1x-7.3.fragment")
                         " >> .config"))
                (invoke "make" "ARCH=arm64" "olddefconfig")))))))
    (synopsis "Linux kernel for the F(x)tec Pro1X (QX1050 / SM6115)")
    (description
     "Mainline Linux 7.3 with moWerk's Pro1-X series, with device patches
for the F(x)tec Pro1X: AW9523B keyboard matrix, BOE DSI panel (60 Hz),
Goodix GT9286 touch, WCN3950 Bluetooth, AW86224 haptics, q6voice DSP bridge,
IMX582/DW9800 rear camera, S5K4H7 front camera, LED controllers, PM and more.")
    (license license:gpl2)))
