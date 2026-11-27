;;; fxtec-pro1x/packages/usb-video.scm — the screen as a USB webcam
;;;
;;; device/usb-video: pro1x-usb-gadget (root: the configfs gadget with the
;;; UVC function beside the network and serial ones), pro1x-uvc-feed (the
;;; UVC requests and the frames on the gadget's V4L2 device) and
;;; pro1x-usb-video (the user's start and stop).  The kernel needs
;;; CONFIG_USB_CONFIGFS_F_UVC (device/kernel/pro1x-7.3.fragment).
;;; State: built, not yet run on the phone (2026-11-27).

(define-module (fxtec-pro1x packages usb-video)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages cast)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages video)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define-public pro1x-usb-video
  (package
    (name "pro1x-usb-video")
    (version "0.1")
    (source (local-file (repository-file "device/usb-video") "pro1x-usb-video"
                        #:recursive? #t))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f
           #:phases
           #~(modify-phases %standard-phases
               (delete 'configure)
               (replace 'build
                 (lambda _
                   (invoke #$(cc-for-target) "-std=gnu11" "-O2" "-Wall"
                           "-o" "pro1x-uvc-feed" "pro1x-uvc-feed.c")))
               (replace 'check
                 ;; The frame parser on a made-up PXSC record.
                 (lambda* (#:key tests? #:allow-other-keys)
                   (when tests?
                     (invoke "sh" "-c"
                             "printf 'PXSC\\004\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\001\\145\\210\\204' | ./pro1x-uvc-feed -t h264 | grep -q '^1 frames'"))))
               (replace 'install
                 (lambda _
                   (let ((bin (string-append #$output "/bin")))
                     (install-file "pro1x-uvc-feed" bin)
                     (install-file "pro1x-usb-gadget" bin)
                     (install-file "pro1x-usb-video" bin)
                     (for-each
                      (lambda (script)
                        (let ((file (string-append bin "/" script)))
                          (chmod file #o755)
                          (patch-shebang file (list (string-append
                                                     #$(this-package-input "bash-minimal")
                                                     "/bin")))))
                      '("pro1x-usb-gadget" "pro1x-usb-video"))
                     ;; The producers, found by pro1x-usb-video's shell.
                     (wrap-program (string-append bin "/pro1x-usb-video")
                       `("PATH" ":" suffix
                         ,(list (string-append #$output "/bin")
                                #$(file-append pro1x-screencast "/bin")
                                #$(file-append wf-recorder "/bin")
                                #$(file-append coreutils "/bin")
                                #$(file-append grep "/bin"))))
                     ;; Its tools: mount, mountpoint, modprobe, sed-free.
                     (wrap-program (string-append bin "/pro1x-usb-gadget")
                       `("PATH" ":" suffix
                         ,(list #$(file-append kmod "/bin")
                                #$(file-append util-linux "/bin")
                                #$(file-append coreutils "/bin")
                                #$(file-append grep "/bin"))))))))))
    (native-inputs (list linux-libre-headers))
    (inputs (list bash-minimal coreutils grep kmod pro1x-screencast util-linux
                  wf-recorder))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Serve the phone's screen as a USB webcam")
    (description "pro1x-usb-video makes the Pro¹x a composite USB gadget
with its network and serial functions plus a UVC camera, and feeds the
camera with the screen: H.264 from the Venus encoder (pro1x-screencast) or
MJPEG from wf-recorder, at the size and rate the computer asks for.  Any
program that opens a webcam on the computer shows the phone's screen.")
    (license license:gpl3+)))
