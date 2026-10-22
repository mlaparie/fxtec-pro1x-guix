;;; fxtec-pro1x/packages/misc.scm — small Qualcomm userspace tools + patched packages
;;;
;;; Packages:
;;;   qbootctl         — mark A/B boot slot as successful
;;;   tqftpserv        — deliver modem firmware over QRTR/TFTP
;;;   rmtfs            — Qualcomm remote filesystem (modemst1/2, fsg, fsc)
;;;   hexagonrpcd      — serve ADSP sensor config over FastRPC
;;;   libcamera-pro1x  — libcamera patched for IMX582 + S5K4H7
;;;   cameractrl       — V4L2 camera controls GUI (focus/exposure)
;;;   phoc-pro1x       — phoc patched to ignore SW_KEYPAD_SLIDE

(define-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages base)
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages python)
  #:use-module (gnu packages photo)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages video)
  #:use-module (gnu packages window-management)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (libqrtr
            qbootctl
            tqftpserv
            rmtfs
            hexagonrpcd
            libcamera-pro1x
            cameractrl
            gmobile-0.7
            phoc
            phoc-pro1x))

;;; ---------------------------------------------------------------------------
;;; libqrtr — Qualcomm IPC Router userspace library
;;; Provides libqrtr.so and qrtr.pc (needed by rmtfs, tqftpserv, hexagonrpcd).
;;; ---------------------------------------------------------------------------
(define-public libqrtr
  (package
    (name "libqrtr")
    (version "unstable-29e36ae")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/linux-msm/qrtr")
             (commit "29e36ae164389580a0f8ea7a7fdb728140ae978d")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0vg5d1jkfy1530jsl4l1x1lvn3hzf3nz0m9351nblf19l4byflax"))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config))
    (arguments (list #:tests? #f))
    (home-page "https://github.com/linux-msm/qrtr")
    (synopsis "Qualcomm IPC Router userspace library")
    (description
     "libqrtr provides a C API to the Linux kernel's QRTR (Qualcomm IPC Router)
socket layer, used by rmtfs, tqftpserv and hexagonrpcd to communicate with
Qualcomm modem and ADSP subsystems.")
    (license license:bsd-3)))

;;; ---------------------------------------------------------------------------
;;; qbootctl — Qualcomm A/B boot slot control
;;; ---------------------------------------------------------------------------
(define-public qbootctl
  (package
    (name "qbootctl")
    (version "unstable-39a6e6d")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/linux-msm/qbootctl")
             (commit "39a6e6daaf029fb0a083777679a15ea2c18f72de")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "01hm5f50z31mqdyg4rvqp4bnqiq8rrbi07bym6zr5qj9si9w544n"))))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f
           #:make-flags #~(list (string-append "PREFIX=" #$output))
           #:phases
           #~(modify-phases %standard-phases
               (delete 'configure))))
    (home-page "https://github.com/linux-msm/qbootctl")
    (synopsis "Mark Qualcomm A/B boot slots successful")
    (description
     "qbootctl marks the active A/B boot slot as successfully booted, preventing
the ABL from reverting to fastboot after a hard reboot.")
    (license license:gpl2+)))

;;; ---------------------------------------------------------------------------
;;; tqftpserv — TFTP server for Qualcomm modem firmware (over QRTR)
;;; ---------------------------------------------------------------------------
(define-public tqftpserv
  (package
    (name "tqftpserv")
    (version "unstable-0bf5b98")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/andersson/tqftpserv")
             (commit "0bf5b98c24229b0042554d99bb1509d813219f36")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0fb9dns3h20y9n4b57cnyb53j8yvlm8fm6n2gxd04iwwk3nfylmi"))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config))
    (inputs (list libqrtr))
    (arguments
     (list #:tests? #f
           #:phases
           #~(modify-phases %standard-phases
               (add-before 'configure 'fix-firmware-path
                 (lambda _
                   (substitute* "translate.c"
                     (("\"/lib/firmware/\"")
                      "\"/run/current-system/firmware/\"")))))))
    (home-page "https://github.com/andersson/tqftpserv")
    (synopsis "TFTP server that delivers modem firmware over QRTR")
    (description
     "tqftpserv answers TFTP requests from the Qualcomm modem over the QRTR
inter-processor bus, serving firmware blobs from the firmware directory.")
    (license license:bsd-3)))

;;; ---------------------------------------------------------------------------
;;; rmtfs — Qualcomm remote filesystem service
;;; ---------------------------------------------------------------------------
(define-public rmtfs
  (package
    (name "rmtfs")
    (version "unstable-b30a3eb")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/andersson/rmtfs")
             (commit "b30a3eb38f9af283f18dbd3c7755653efc52c094")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0hjp0lzv2hkbawjrbnkk98rrrfb1g3x1iifbilbkcabrik7smpcg"))))
    (build-system gnu-build-system)
    (inputs (list libqrtr eudev))
    (arguments
     (list #:tests? #f
           #:make-flags #~(list "CC=gcc"
                                (string-append "prefix=" #$output))
           #:phases #~(modify-phases %standard-phases (delete 'configure))))
    (home-page "https://github.com/andersson/rmtfs")
    (synopsis "Qualcomm remote filesystem service (modemst1/2, fsg, fsc)")
    (description
     "rmtfs exposes modem EFS partitions over QRTR so the modem remoteproc can
read and write modemst1/2, fsg and fsc storage without a full Android userspace.")
    (license license:bsd-3)))

;;; ---------------------------------------------------------------------------
;;; hexagonrpcd — serve ADSP sensor configuration via FastRPC
;;; The version used here is the linux-msm PR #27 branch which adds the
;;; sns_registry interface needed for sensor initialisation on the Pro1X.
;;; ---------------------------------------------------------------------------
(define-public hexagonrpcd
  (package
    (name "hexagonrpcd")
    (version "0.5.0-unstable-pr27")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/linux-msm/hexagonrpc")
             (commit "40e50412812adce9dddc2be9a4510ebce05eef89")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "09hf7v2ix0j6bvx90dnxfgy9hz8var0qjrbvhdmh6bnayyydampr"))
       (patches
        (list
         (local-file "../../packages/hexagonrpc-sns-registry.patch"
                     "hexagonrpc-sns-registry.patch")))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config))
    (inputs (list libqrtr))
    (arguments (list #:tests? #f))
    (home-page "https://github.com/linux-msm/hexagonrpc")
    (synopsis "Serve ADSP sensor configuration via FastRPC (hexagonrpcd)")
    (description
     "hexagonrpcd implements the FastRPC listener that the Qualcomm ADSP calls
to fetch sensor configuration and registry files from the Linux filesystem.
This version includes the sns_registry interface required by the Pro1X ADSP
sensor stack (linux-msm/hexagonrpc pull request 27).")
    (license license:bsd-3)))

;;; ---------------------------------------------------------------------------
;;; libcamera-pro1x — libcamera + S5K4H7 and IMX582 sensor patches
;;; ---------------------------------------------------------------------------
(define-public libcamera-pro1x
  (package
    (inherit libcamera)
    (name "libcamera-pro1x")
    (arguments
     (substitute-keyword-arguments (package-arguments libcamera)
       ((#:phases phases)
        #~(modify-phases #$phases
            (add-after 'install 'install-sensor-tuning
              (lambda _
                (let ((ipa (string-append #$output
                                          "/share/libcamera/ipa/simple")))
                  (mkdir-p ipa)
                  (copy-file #$(local-file "../../device/libcamera/imx582.yaml")
                             (string-append ipa "/imx582.yaml"))
                  (copy-file #$(local-file "../../device/libcamera/s5k4h7.yaml")
                             (string-append ipa "/s5k4h7.yaml")))))))))
    (source
     (origin
       (inherit (package-source libcamera))
       (patches
        (append
         (origin-patches (package-source libcamera))
         (list
          (local-file "../../device/libcamera/s5k4h7-sensor.patch"
                      "s5k4h7-sensor.patch")
          (local-file "../../device/libcamera/imx582-sensor.patch"
                      "imx582-sensor.patch"))))))
    (synopsis "libcamera with S5K4H7 (front) and IMX582 (rear) sensor support")
    (description
     "libcamera built with driver and tuning-file support for the Pro1X cameras:
S5K4H7 5 MP front sensor and IMX582 48 MP rear sensor with DW9800 AF driver.")))

;;; ---------------------------------------------------------------------------
;;; cameractrl — V4L2 camera control GUI (focus, exposure)
;;; ---------------------------------------------------------------------------
(define-public cameractrl
  (package
    (name "cameractrl")
    (version "unstable-4c8ac34")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.com/NekoCWD/cameractrl")
             (commit "4c8ac34295df52c5f887a9e51ec64f54ef26c636")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0f9dfg26lylq92894hcv7c6l5dwnibnj7rzb0m43py7n7w5p92p2"))))
    (build-system meson-build-system)
    (native-inputs
     (list pkg-config vala blueprint-compiler
           `(,glib "bin") desktop-file-utils))
    (inputs
     (list glib gtk libadwaita libgudev
           ;; gtk4-layer-shell not yet in Guix; add when available:
           ;; gtk4-layer-shell
           ))
    (synopsis "Camera focus/exposure controls for V4L2 sub-devices on mobile Linux")
    (description
     "cameractrl provides a Libadwaita/GTK4 GUI for adjusting V4L2 sub-device
controls (autofocus, manual focus distance, exposure) on phones with the Pro1X
camera hardware.  Run as: cameractr")
    (home-page "https://gitlab.com/NekoCWD/cameractrl")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; gmobile-0.7 — newer gmobile required by phoc >= 0.45
;;; Guix ships 0.2.1; phoc 0.58.0 needs >= 0.6.0.
;;; ---------------------------------------------------------------------------
(define-public gmobile-0.7
  (package
    (inherit gmobile)
    (version "0.7.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.gnome.org/World/Phosh/gmobile")
             (commit (string-append "v" version))))
       (file-name (git-file-name "gmobile" version))
       (sha256
        (base32 "1cya0aad763v07ss1qx7g5fnqmnxznhrnw4arr1956kxa00qf68c"))))
    (native-inputs
     (modify-inputs (package-native-inputs gmobile)
       (append vala)))))

;;; gvdb is an unconditional meson subproject of phoc; pre-seed the dir.
(define phoc-gvdb-source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://gitlab.gnome.org/GNOME/gvdb")
          (commit "4758f6fb7f889e074e13df3f914328f3eecb1fd3")))
    (file-name "gvdb-checkout")
    (sha256
     (base32 "129ln7rldafdkcf2kxdazckyp3xzxnk0xw33l2kzfc3bz4fahsp2"))))

;;; ---------------------------------------------------------------------------
;;; phoc — Wayland compositor for phones (Phosh)
;;; ---------------------------------------------------------------------------
(define-public phoc
  (package
    (name "phoc")
    (version "0.58.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.gnome.org/World/Phosh/phoc")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0xz5gxxpxm77padj98n3zgif8nvj5danvn2cfb1k56bvv1ws7azc"))))
    (build-system meson-build-system)
    (native-inputs
     (list gettext-minimal gobject-introspection pkg-config
           `(,glib "bin")))
    (inputs
     (list wlroots glib json-glib mesa
           gnome-desktop gsettings-desktop-schemas gmobile-0.7
           libinput eudev libdrm pixman
           wayland wayland-protocols libxkbcommon))
    (arguments
     (list #:tests? #f
           #:configure-flags #~(list "-Dtests=false")
           #:phases
           #~(modify-phases %standard-phases
               (add-after 'unpack 'seed-gvdb-subproject
                 (lambda _
                   (copy-recursively #$phoc-gvdb-source
                                     "subprojects/gvdb"))))))
    (home-page "https://gitlab.gnome.org/World/Phosh/phoc")
    (synopsis "Wayland compositor for mobile phones")
    (description
     "phoc is a Wayland compositor for phones, based on wlroots 0.20.
Used as the compositor for the Phosh mobile shell.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; phoc-pro1x — phoc patched to ignore SW_KEYPAD_SLIDE
;;; Without the patch, phoc aborts whenever the keyboard slider is moved,
;;; crash-looping Phosh.
;;; ---------------------------------------------------------------------------
(define-public phoc-pro1x
  (package
    (inherit phoc)
    (name "phoc-pro1x")
    (source
     (origin
       (inherit (package-source phoc))
       (patches
        (append
         (origin-patches (package-source phoc))
         (list
          (local-file "../../device/phoc/ignore-unknown-switch.patch"
                      "phoc-ignore-unknown-switch.patch"))))))
    (synopsis "phoc compositor patched to ignore SW_KEYPAD_SLIDE (Pro1X keyboard slider)")))
