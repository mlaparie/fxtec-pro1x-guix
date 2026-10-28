;;; fxtec-pro1x/packages/misc.scm — small Qualcomm userspace tools + patched packages
;;;
;;; Packages:
;;;   qbootctl          — mark A/B boot slot as successful
;;;   tqftpserv         — deliver modem firmware over QRTR/TFTP
;;;   rmtfs             — Qualcomm remote filesystem (modemst1/2, fsg, fsc)
;;;   hexagonrpcd       — serve ADSP sensor config over FastRPC
;;;   pro1x-xts-encrypt — host tool: offline AES-XTS-plain64 encryption for FDE images
;;;   libcamera-pro1x   — libcamera patched for IMX582 + S5K4H7
;;;   cameractrl        — V4L2 camera controls GUI (focus/exposure)
;;;   phoc-pro1x        — phoc patched to ignore SW_KEYPAD_SLIDE
;;;   callaudiod        — call audio routing daemon (needed by phosh/libcall-ui)
;;;   feedbackd-0.8     — haptic/audio/visual feedback daemon >= 0.7 (required by phosh 0.56+)
;;;   phosh             — Phosh mobile shell
;;;   phosh-pro1x       — Phosh configured to use phoc-pro1x compositor

(define-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages base)
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages aidc)
  #:use-module (gnu packages fribidi)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages polkit)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages python)
  #:use-module (gnu packages photo)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages video)
  #:use-module (gnu packages window-management)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (libqrtr
            qbootctl
            tqftpserv
            rmtfs
            hexagonrpcd
            pro1x-xts-encrypt
            libcamera-pro1x
            cameractrl
            gmobile-0.7
            phoc
            phoc-pro1x
            libqmi-1.36
            modem-manager-1.24
            callaudiod
            feedbackd-0.8
            phosh
            phosh-pro1x))

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
       (method url-fetch)
       (uri (string-append
             "https://github.com/linux-msm/qrtr/archive/"
             "29e36ae164389580a0f8ea7a7fdb728140ae978d.tar.gz"))
       (sha256
        (base32 "0kmfvm2lr69rxfwpns841c882l4l7064bdfrglp318508z24dy36"))))
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
       (method url-fetch)
       (uri (string-append
             "https://github.com/linux-msm/qbootctl/archive/"
             "39a6e6daaf029fb0a083777679a15ea2c18f72de.tar.gz"))
       (sha256
        (base32 "0yxnx26mni9h712nayp3pi51qlrzcwydhxshmznsr79h03f8zilx"))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config))
    (arguments (list #:tests? #f))
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
       (method url-fetch)
       (uri (string-append
             "https://github.com/andersson/tqftpserv/archive/"
             "0bf5b98c24229b0042554d99bb1509d813219f36.tar.gz"))
       (sha256
        (base32 "0n6b7qxzqrjkbn55y6c98bxvl29z96jgy4rjzj3nka39b9x4vyg0"))))
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
       (method url-fetch)
       (uri (string-append
             "https://github.com/andersson/rmtfs/archive/"
             "b30a3eb38f9af283f18dbd3c7755653efc52c094.tar.gz"))
       (sha256
        (base32 "09sbikvzm8j7nmbrg8idr75sq5h96gj04k29wz04gcj8mhfab385"))))
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
;;; PR #27 (sns_registry interface) was never merged; apply it as a patch.
;;; The upstream repo was force-pushed; switched to url-fetch tarball.
;;; ---------------------------------------------------------------------------
(define-public hexagonrpcd
  (package
    (name "hexagonrpcd")
    (version "0.5.0-unstable-da7a374")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/linux-msm/hexagonrpc/archive/"
             "da7a3742ab8d5273a281b70ee11f16fb2cb6a690.tar.gz"))
       (sha256
        (base32 "0df4af0n2fx3bx6b24ajva177mnvrk1clhpclrmpd8ljrwyva6k5"))
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
;;; pro1x-xts-encrypt — host tool: offline AES-XTS-plain64 for FDE image creation
;;; Encrypts a disk image the same way dm-crypt does for a LUKS2 volume, without
;;; needing root or device-mapper.  Used by scripts/flash-encrypted.sh.
;;; ---------------------------------------------------------------------------
(define-public pro1x-xts-encrypt
  (package
    (name "pro1x-xts-encrypt")
    (version "0.1")
    (source (local-file "../../device/fde/xts-encrypt.c"
                        "xts-encrypt.c"))
    (build-system trivial-build-system)
    ;; Host tool: compiled for the build machine (x86_64 or whatever the host is).
    (native-inputs
     (list (@ (gnu packages commencement) gcc-toolchain)
           linux-libre-headers
           openssl))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((src   #$source)
                 (tc    #$(this-package-native-input "gcc-toolchain"))
                 (khdrs #$(this-package-native-input "linux-libre-headers"))
                 (ssl   #$(this-package-native-input "openssl"))
                 (out   #$output)
                 (bin   (string-append out "/bin")))
            (mkdir-p bin)
            (setenv "PATH" (string-append tc "/bin"))
            (invoke "gcc" "-O2" "-o" (string-append bin "/pro1x-xts-encrypt")
                    src
                    (string-append "-I" ssl "/include")
                    (string-append "-I" khdrs "/include")
                    (string-append "-L" ssl "/lib")
                    "-lcrypto")))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Offline AES-XTS-plain64 encryption for LUKS2 image creation")
    (description
     "pro1x-xts-encrypt encrypts a disk image sector-by-sector using
AES-256-XTS-plain64 with the same tweak convention as dm-crypt, without
needing root or device-mapper.  It is used by scripts/flash-encrypted.sh
to build an FDE userdata image on the host before flashing.")
    (license license:gpl2+)))

;;; ---------------------------------------------------------------------------
;;; libcamera-pro1x — libcamera + S5K4H7 and IMX582 sensor patches
;;; ---------------------------------------------------------------------------
(define-public libcamera-pro1x
  (package
    (inherit libcamera)
    (name "libcamera-pro1x")
    (arguments
     (substitute-keyword-arguments (package-arguments libcamera)
       ((#:tests? _ #f) #f)
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
    (version "unstable-17f1b82")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.com/NekoCWD/cameractrl/-/archive/"
             "17f1b82d5dbe05abf7ccc1f9dd52d6cc23e48230"
             "/cameractrl-17f1b82d5dbe05abf7ccc1f9dd52d6cc23e48230.tar.gz"))
       (sha256
        (base32 "13w0v4vmx7pd3pdyp8xsxd8vik5xli8w23mqfvmkq64gd6w40q7c"))))
    (build-system meson-build-system)
    (native-inputs
     (list pkg-config vala blueprint-compiler gettext-minimal
           `(,glib "bin") `(,gtk "bin") desktop-file-utils))
    (inputs
     (list glib gtk libadwaita libgudev gtk4-layer-shell))
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
       (method url-fetch)
       (uri (string-append
             "https://gitlab.gnome.org/World/Phosh/gmobile/-/archive/v"
             version "/gmobile-v" version ".tar.gz"))
       (sha256
        (base32 "1mhb34xw58cblw8v5w0a17309fcpn439bl0rad21nq11iyh76wsr"))))
    (native-inputs
     (modify-inputs (package-native-inputs gmobile)
       (delete "gobject-introspection")
       (append vala)))
    (arguments
     (substitute-keyword-arguments (package-arguments gmobile)
       ((#:configure-flags flags #~'())
        #~(append #$flags (list "-Dintrospection=false")))))))

;;; gvdb is an unconditional meson subproject of phoc; pre-seed the dir.
(define phoc-gvdb-source
  (origin
    (method url-fetch)
    (uri (string-append
          "https://gitlab.gnome.org/GNOME/gvdb/-/archive/"
          "4758f6fb7f889e074e13df3f914328f3eecb1fd3"
          "/gvdb-4758f6fb7f889e074e13df3f914328f3eecb1fd3.tar.gz"))
    (sha256
     (base32 "1mnv0mgpffdkq6fxdiyxylps8qy9z1js4pnz2nllci9i72yq0dns"))))

;;; ---------------------------------------------------------------------------
;;; phoc — Wayland compositor for phones (Phosh)
;;; ---------------------------------------------------------------------------
(define-public phoc
  (package
    (name "phoc")
    (version "0.56.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.gnome.org/World/Phosh/phoc/-/archive/v"
             version "/phoc-v" version ".tar.gz"))
       (sha256
        (base32 "02y4zda49rfl7j399c8kvwllw51kfawgm7d4yj715yq50kvk2dr3"))))
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
                   (mkdir-p "subprojects/gvdb")
                   (invoke "tar" "xf" #$phoc-gvdb-source
                           "-C" "subprojects/gvdb"
                           "--strip-components=1"))))))
    (home-page "https://gitlab.gnome.org/World/Phosh/phoc")
    (synopsis "Wayland compositor for mobile phones")
    (description
     "phoc is a Wayland compositor for phones, based on unpatched wlroots 0.20.
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

;;; ---------------------------------------------------------------------------
;;; libqmi-1.36 — libqmi >= 1.36 required by ModemManager 1.24
;;; Guix ships 1.34.0.
;;; ---------------------------------------------------------------------------
(define-public libqmi-1.36
  (package
    (inherit libqmi)
    (version "1.36.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.freedesktop.org/mobile-broadband/libqmi"
             "/-/archive/" version "/libqmi-" version ".tar.gz"))
       (sha256
        (base32 "14whz2d0b1h2ska89pn7b5zlhqk68fp74vbf28kqm9qnv7yzlm72"))))
    (arguments
     (list #:configure-flags
           #~(list "-Dmbim_qmux=false"  ; Pro1X uses native QMI, not QMI-over-MBIM
                   "-Dman=false"
                   "-Dintrospection=false"
                   "-Dfuzzer=false")))))

;;; ---------------------------------------------------------------------------
;;; modem-manager-1.24 — ModemManager >= 1.24 required by phosh 0.56+
;;; Guix ships 1.22.0; phosh's mm-glib dependency needs >= 1.24.
;;; ---------------------------------------------------------------------------
(define-public modem-manager-1.24
  (package
    (inherit modem-manager)
    (version "1.24.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.freedesktop.org/mobile-broadband/ModemManager"
             "/-/archive/" version "/ModemManager-" version ".tar.gz"))
       (sha256
        (base32 "1ix74pj05isl9fbyxyi4ainv5igv1n986i41xp50pc5c4jxndqah"))))
    (arguments
     (substitute-keyword-arguments (package-arguments modem-manager)
       ((#:configure-flags flags)
        #~(list (string-append "-Dudevdir=" #$output "/lib/udev")
                "-Dsystemdsystemunitdir=no"
                "-Dvapi=false"
                "-Dtests=false"
                "-Dman=false"
                "-Dmbim=false"          ; Pro1X uses QMI/QRTR, not MBIM; avoids mbim-glib >= 1.32 req
                "-Dintrospection=false"
                "-Dplugin_qcom_soc=enabled"))))
    (inputs
     (modify-inputs (package-inputs modem-manager)
       (replace "libqmi" libqmi-1.36)))))

;;; callaudiod — call audio routing daemon
;;; Required at build time by the libcall-ui subproject embedded in Phosh.
;;; ---------------------------------------------------------------------------
(define-public callaudiod
  (package
    (name "callaudiod")
    (version "0.1.10")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.com/mobian1/callaudiod/-/archive/"
             version "/callaudiod-" version ".tar.gz"))
       (sha256
        (base32 "0jkh9axrcyz920s30z3vfp1rds98dlq18f7wcycrnp7h4vmw0w3y"))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config `(,glib "bin")))
    (inputs (list alsa-lib glib pulseaudio))
    (arguments (list #:tests? #f))
    (home-page "https://gitlab.com/mobian1/callaudiod")
    (synopsis "Daemon for audio routing during phone calls")
    (description
     "callaudiod routes audio between earpiece, speaker and headphones during
phone calls via ALSA and PulseAudio.  Its library (libcallaudio-0.1) is
required by the libcall-ui subproject embedded in Phosh.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; feedbackd-0.8 — haptic/audio/visual feedback daemon, >= 0.7 series
;;; Guix ships 0.6.0; Phosh 0.56+ requires libfeedback >= 0.7.0.
;;; ---------------------------------------------------------------------------
(define-public feedbackd-0.8
  (package
    (name "feedbackd")
    (version "0.8.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.freedesktop.org/feedbackd/feedbackd/-/archive/v"
             version "/feedbackd-v" version ".tar.gz"))
       (sha256
        (base32 "09g953k5jwki6c0nj78xl2alhhkhk3q0dwx6jpxv5dy67i5nkzaa"))))
    (build-system meson-build-system)
    (native-inputs
     (list pkg-config vala gobject-introspection `(,glib "bin")))
    (inputs (list glib gsound json-glib libgudev gmobile-0.7))
    (arguments
     (list #:tests? #f
           #:configure-flags
           #~(list "-Dintrospection=disabled"
                   "-Dvapi=false"
                   "-Dudev=false"
                   "-Dgtk_doc=false"
                   "-Dtests=false")))
    (home-page "https://gitlab.freedesktop.org/feedbackd/feedbackd")
    (synopsis "Haptic/audio/visual feedback daemon (0.8 series)")
    (description
     "feedbackd provides a D-Bus daemon for delivering haptic, audio and
visual feedback events.  This 0.8 series supplies libfeedback >= 0.7.0 as
required by Phosh 0.56+.")
    (license license:lgpl2.1+)))

;;; gvc and libcall-ui tarballs pre-seeded as Phosh meson subprojects.
(define phosh-gvc-source
  (origin
    (method url-fetch)
    (uri "https://gitlab.gnome.org/GNOME/libgnome-volume-control/-/archive/d2442f455844e5292cb4a74ffc66ecc8d7595a9f/libgnome-volume-control-d2442f455844e5292cb4a74ffc66ecc8d7595a9f.tar.gz")
    (sha256
     (base32 "1c6wpymfn5sf609d3nws3hbrxdnww4r8pfhh5i4j2jl93kiwara5"))))

(define phosh-libcall-ui-source
  (origin
    (method url-fetch)
    (uri "https://gitlab.gnome.org/World/Phosh/libcall-ui/-/archive/v0.1.5/libcall-ui-v0.1.5.tar.gz")
    (sha256
     (base32 "167hqq4npnyvh6sqhvb7kgwdk29snhnh3hm1lsrik1yxsp8xzais"))))

;;; ---------------------------------------------------------------------------
;;; phosh — Phosh mobile shell (lock screen, home screen, status bar, OSK)
;;; ---------------------------------------------------------------------------
(define-public phosh
  (package
    (name "phosh")
    (version "0.56.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.gnome.org/World/Phosh/phosh/-/archive/v"
             version "/phosh-v" version ".tar.gz"))
       (sha256
        (base32 "0md2vg9fi3vccjm906w83hj3g7dwwc7b0h2b532cayvkk6hb01m0"))))
    (build-system meson-build-system)
    (native-inputs
     (list pkg-config
           `(,glib "bin")
           `(,gtk+ "bin")
           gettext-minimal
           python
           wayland            ; provides wayland-scanner
           desktop-file-utils))
    (inputs
     (list appstream
           callaudiod
           elogind
           evolution-data-server
           feedbackd-0.8
           fribidi
           gcr-3
           glib
           gmobile-0.7
           gnome-bluetooth
           gnome-desktop
           gsettings-desktop-schemas
           gtk+
           libgudev
           libhandy
           libsecret
           libsoup
           linux-pam
           modem-manager-1.24
           qrcodegen-cpp
           network-manager
           polkit
           pulseaudio
           upower
           wayland
           wayland-protocols
           libxkbcommon))
    (arguments
     (list #:tests? #f
           #:configure-flags
           #~(list (string-append "-Dcompositor=" #$(file-append phoc "/bin/phoc"))
                   "-Dtests=false"
                   "-Dsearchd=false"
                   "-Dbindings-lib=false"
                   "-Dgtk_doc=false"
                   "-Dman=false"
                   "-Dintrospection=false"
                   "-Dcallui-i18n=false"
                   "-Dlockscreen-plugins=false")
           #:phases
           #~(modify-phases %standard-phases
               (add-after 'unpack 'seed-subprojects
                 (lambda _
                   (mkdir-p "subprojects/gvc")
                   (invoke "tar" "xf" #$phosh-gvc-source
                           "--strip-components=1" "-C" "subprojects/gvc")
                   (mkdir-p "subprojects/libcall-ui")
                   (invoke "tar" "xf" #$phosh-libcall-ui-source
                           "--strip-components=1" "-C" "subprojects/libcall-ui"))))))
    (home-page "https://gitlab.gnome.org/World/Phosh/phosh")
    (synopsis "Phosh mobile shell for Wayland")
    (description
     "Phosh is a pure Wayland mobile shell for phones and tablets, providing a
lock screen, status bar, notification drawer, home screen and app launcher.
It runs on top of the Phoc compositor.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; phosh-pro1x — Phosh built with phoc-pro1x as the managed compositor
;;; phoc-pro1x ignores SW_KEYPAD_SLIDE so sliding the keyboard open does not
;;; crash-loop the compositor when Phosh manages phoc itself.
;;; ---------------------------------------------------------------------------
(define-public phosh-pro1x
  (package
    (inherit phosh)
    (name "phosh-pro1x")
    (source
     (origin
       (inherit (package-source phosh))
       (patches
        (append (origin-patches (package-source phosh))
                (list (local-file "../../device/phosh/fix-home-bar-height.patch"))))))
    (arguments
     (substitute-keyword-arguments (package-arguments phosh)
       ((#:configure-flags _)
        #~(list (string-append "-Dcompositor=" #$(file-append phoc-pro1x "/bin/phoc"))
                "-Dtests=false"
                "-Dsearchd=false"
                "-Dbindings-lib=false"
                "-Dgtk_doc=false"
                "-Dman=false"
                "-Dintrospection=false"
                "-Dcallui-i18n=false"
                "-Dlockscreen-plugins=false"))
       ((#:phases phases)
        #~(modify-phases #$phases
            (add-after 'install 'install-missing-schemas
              (lambda* (#:key outputs #:allow-other-keys)
                (let* ((out (assoc-ref outputs "out"))
                       (schema-dir (string-append out "/share/glib-2.0/schemas")))
                  (for-each
                   (lambda (src)
                     (copy-file src (string-append schema-dir "/" (basename src))))
                   (list
                    #$(local-file "../../device/phosh/org.gnome.settings-daemon.peripherals.gschema.xml")
                    #$(local-file "../../device/phosh/org.gnome.settings-daemon.plugins.gschema.xml")
                    #$(local-file "../../device/phosh/org.gnome.settings-daemon.plugins.power.gschema.xml")
                    #$(local-file "../../device/phosh/gnome-shell-keybindings.gschema.xml")))
                  (invoke "glib-compile-schemas" schema-dir))))))))
    (synopsis "Phosh mobile shell configured for the F(x)tec Pro1X (phoc-pro1x compositor)")))
