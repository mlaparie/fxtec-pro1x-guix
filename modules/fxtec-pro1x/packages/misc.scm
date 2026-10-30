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
;;;   sway-launcher-desktop — fzf application launcher for sway (in a terminal)
;;;   pro1x-sway-config — default sway config, i3status-rust bar, window switcher

(define-module (fxtec-pro1x packages misc)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages terminals)
  #:use-module (gnu packages web)            ; jq
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages serialization)  ; libyaml
  #:use-module (gnu packages aidc)
  #:use-module (gnu packages fribidi)
  #:use-module (gnu packages dns)           ; c-ares
  #:use-module (gnu packages glib)
  #:use-module (gnu packages messaging)     ; libphonenumber
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages image)        ; grim, slurp
  #:use-module (gnu packages imagemagick)
  #:use-module (gnu packages package-management) ; guix-backgrounds
  #:use-module (gnu packages fonts)
  #:use-module (gnu packages hunspell)
  #:use-module (gnu packages linux)
  #:use-module (nonguix build-system binary)  ; bluetuith
  #:use-module (gnu packages perl)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages protobuf)
  #:use-module (gnu packages polkit)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages python)
  #:use-module (gnu packages photo)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages video)
  #:use-module (gnu packages window-management)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix git-download)
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
            phosh-pro1x
            sway-launcher-desktop
            pro1x-sway-config))

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
;;; Commit 40e5041 (the NixOS port's), not da7a374: it lets the ADSP write
;;; into its sensor registry.  With da7a374 the writes were refused, the
;;; Sensor Core took the whole ADSP down at about 12 s ("fatal error
;;; received: ... sensor_process ... SNS_REG_INIT"), and audio, which runs
;;; on the same DSP, failed afterwards (AFE -110, wcd937x -16).
;;; ---------------------------------------------------------------------------
(define-public hexagonrpcd
  (package
    (name "hexagonrpcd")
    (version "0.5.0-unstable-40e5041")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/linux-msm/hexagonrpc/archive/"
             "40e50412812adce9dddc2be9a4510ebce05eef89.tar.gz"))
       (sha256
        (base32 "0q8q76pk343xj45g5zfi537hrap17ph3wvfyrcf4zpy0b8rzharj"))
       (patches
        (list
         (local-file (repository-file "packages/hexagonrpc-sns-registry.patch")
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
    (source (local-file (repository-file "device/fde/xts-encrypt.c")
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
                  (copy-file #$(local-file (repository-file "device/libcamera/imx582.yaml"))
                             (string-append ipa "/imx582.yaml"))
                  (copy-file #$(local-file (repository-file "device/libcamera/s5k4h7.yaml"))
                             (string-append ipa "/s5k4h7.yaml")))))))))
    (source
     (origin
       (inherit (package-source libcamera))
       (patches
        (append
         (origin-patches (package-source libcamera))
         (list
          (local-file (repository-file "device/libcamera/s5k4h7-sensor.patch")
                      "s5k4h7-sensor.patch")
          (local-file (repository-file "device/libcamera/imx582-sensor.patch")
                      "imx582-sensor.patch"))
         ;; Autofocus, manual exposure and fixes from moWerk's SailfishOS
         ;; port (device/libcamera/af/README).
         (map (lambda (name)
                (local-file (repository-file
                             (string-append "device/libcamera/af/" name))
                            name))
              '("0004-libcamera-software_isp-Let-a-single-point-decide-abo.patch"
                "0005-ipa-ipu3-Move-non-specific-parts-of-Af-to-libipa.patch"
                "0006-libcamera-software_isp-Add-variance-to-stats.patch"
                "0007-ipa-softisp-Add-Af-algorithm.patch"
                "0008-libcamera-software_isp-Add-autofocus-controls.patch"
                "0009-ipa-libipa-Use-autofocus-limits-if-available.patch"
                "0010-software_isp-Compute-an-autofocus-sharpness-value.patch"
                "0011-ipa-libipa-af-Make-the-scan-parameters-configurable.patch"
                "0012-ipa-simple-agc-Manual-analogue-gain-exposure-time-an.patch"
                "0013-software_isp-ipa-simple-af-Focus-on-AfWindows.patch"
                "0014-gstreamer-Serialise-control-access-and-expose-AfStat.patch"
                "0015-ipa-Focus-is-lost-only-when-sharpness-drops-AfModeAu.patch"
                "0016-software_isp-debayer_egl-Centre-the-scaled-crop-stat.patch"
                "0017-simple-Keep-exposure-colour-and-focus-over-a-camera-.patch"))))))
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
;;; wlroots-for-phoc — wlroots with the patch phoc builds its own copy with
;;; phoc 0.56 embeds wlroots 0.20.1 plus one revert (its
;;; subprojects/packagefiles/wlroots): a layer surface may ask for height 0
;;; without top and bottom anchors, meaning "as tall as the content".  Phosh's
;;; home bar relies on it.  Without the revert phosh died with "height 0
;;; requested without setting top and bottom anchors"; a phosh patch giving
;;; the home bar a fixed 15 px height avoided that but left the bar 122 px
;;; below the screen (phosh folds it with a margin computed for its full
;;; height).  Only phoc links against this; sway keeps Guix's wlroots.
;;; ---------------------------------------------------------------------------
(define wlroots-for-phoc
  (package
    (inherit wlroots)
    (name "wlroots-for-phoc")
    (source
     (origin
       (inherit (package-source wlroots))
       (patches
        (append (origin-patches (package-source wlroots))
                (list (local-file
                       (repository-file "device/phoc/wlroots-revert-layer-shell-0-dimension.patch")))))))))

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
     (list wlroots-for-phoc glib json-glib mesa
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
     "phoc is a Wayland compositor for phones, based on wlroots 0.20 with phoc's
layer-shell patch.
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
          (local-file (repository-file "device/phoc/ignore-unknown-switch.patch")
                      "phoc-ignore-unknown-switch.patch")
          ;; No black shield on rotation (experiment, author's dislike).
          (local-file (repository-file "device/phoc/rotation-without-shield.patch")
                      "phoc-rotation-without-shield.patch"))))))
    (synopsis "phoc compositor patched for the Pro1X keyboard slider and rotation")))

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
    ;; The power key wakes the screen only through gnome-session's presence
    ;; interface; this session has no gnome-session (TODO.md).
    (source
     (origin
       (inherit (package-source phosh))
       (patches
        (append (origin-patches (package-source phosh))
                (list (local-file
                       (repository-file "device/phosh/unblank-without-gnome-session.patch"))
                      ;; Brightness without logind: write sysfs directly.
                      (local-file
                       (repository-file "device/phosh/backlight-sysfs-without-logind.patch"))
                      ;; Volume slider above 100% when the setting allows.
                      (local-file
                       (repository-file "device/phosh/volume-above-100-percent.patch"))
                      ;; Keyboard out: keep landscape across lock and unlock.
                      (local-file
                       (repository-file "device/phosh/lockscreen-keep-locked-orientation.patch"))
                      ;; Round volume knob; orange bar above 100%.
                      (local-file
                       (repository-file "device/phosh/volume-bar-amplified.patch"))
                      ;; Torch: numbered flash LEDs, sysfs without logind.
                      (local-file
                       (repository-file "device/phosh/torch-without-logind.patch")))))))
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
                    #$(local-file (repository-file "device/phosh/org.gnome.settings-daemon.peripherals.gschema.xml"))
                    #$(local-file (repository-file "device/phosh/org.gnome.settings-daemon.plugins.gschema.xml"))
                    #$(local-file (repository-file "device/phosh/org.gnome.settings-daemon.plugins.power.gschema.xml"))
                    #$(local-file (repository-file "device/phosh/gnome-shell-keybindings.gschema.xml"))
                    ;; Read by phoc, which aborts at start without it.
                    #$(local-file (repository-file "device/phosh/org.gnome.mutter.gschema.xml"))))
                  ;; Show all apps in the overview, not only adaptive ones.
                  ;; Rotation locked by default: portrait with the keyboard
                  ;; closed (phosh-pro1x-slider), landscape with it out.
                  (call-with-output-file
                      (string-append schema-dir "/90_fxtec-pro1x.gschema.override")
                    (lambda (port)
                      (display "[sm.puri.phosh]\napp-filter-mode=@as []\n
[org.gnome.settings-daemon.peripherals.touchscreen]\norientation-lock=true\n
[org.gnome.settings-daemon.peripherals.touchscreen:Phosh]\norientation-lock=true\n
[org.gnome.desktop.background:Phosh]
picture-uri='file:///run/current-system/profile/share/backgrounds/pro1x/light.png'
picture-uri-dark='file:///run/current-system/profile/share/backgrounds/pro1x/dark.png'
picture-options='zoom'
primary-color='#252a3a'

[org.gnome.desktop.screensaver:Phosh]
picture-uri='file:///run/current-system/profile/share/backgrounds/pro1x/dark.png'
picture-options='zoom'
"
                               port)))
                  (invoke "glib-compile-schemas" schema-dir))))))))
    (synopsis "Phosh mobile shell configured for the F(x)tec Pro1X (phoc-pro1x compositor)")))

;;; ---------------------------------------------------------------------------
;;; mmsd-tng — MMS daemon for ModemManager, which Chatty uses for MMS
;;; Not in Guix.  Without it, MMS did not arrive (author, 2026-10-30): the
;;; notification comes as an SMS, mmsd-tng downloads the message from the
;;; operator's MMSC over the MMS APN (set in Chatty's MMS settings).
;;; Built against this channel's ModemManager 1.24, the running daemon.
;;; Run per session (no D-Bus activation file): phosh-pro1x-shell starts it.
;;; ---------------------------------------------------------------------------
(define-public mmsd-tng
  (package
    (name "mmsd-tng")
    (version "2.6.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.com/kop316/mmsd")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "13yq32m1v8qrfjs5b08vzv6bpqrp80ch9krl1bdnxnf2rqpfqwgy"))))
    (build-system meson-build-system)
    (native-inputs (list pkg-config (list glib "bin")))
    ;; protobuf: libphonenumber's headers include protobuf's.
    (inputs (list c-ares glib libphonenumber libsoup
                  mobile-broadband-provider-info modem-manager-1.24 protobuf))
    (home-page "https://gitlab.com/kop316/mmsd")
    (synopsis "MMS daemon for ModemManager")
    (description
     "mmsd-tng receives and sends MMS messages with a modem driven by
ModemManager, for clients such as Chatty.")
    (license license:gpl2)))

;;; ---------------------------------------------------------------------------
;;; stevia — Phosh's on-screen keyboard (formerly phosh-osk-stub)
;;; Not in Guix.  Without it Phosh had no virtual keyboard ("The name
;;; sm.puri.OSK0 was not provided").  0.56, matching Phosh 0.56.  It uses
;;; logind (through libelogind) only to follow the session's lock state;
;;; without logind it finds no session and carries on.  Started by
;;; phosh-pro1x-shell.
;;; ---------------------------------------------------------------------------
(define-public stevia
  (package
    (name "stevia")
    (version "0.56.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.gnome.org/World/Phosh/stevia")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0lvc6c6nrm7zc5ff7v8c92l7v2ksdicdlshbxk7xjm7rlj3ndn9y"))
       ;; Ours: phoc's device-state protocol optional, so stevia also
       ;; runs in Sway (it never drew its keyboard there); the terminal
       ;; shortcuts bar shown when the keyboard starts on that layout (in
       ;; Sway, with only terminals, it never appeared).
       (patches
        (list (local-file
               (repository-file "device/phosh/stevia-optional-device-state.patch")
               "stevia-optional-device-state.patch")
              (local-file
               (repository-file "device/phosh/stevia-shortcuts-bar-at-start.patch")
               "stevia-shortcuts-bar-at-start.patch")))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #t
      #:tests? #f                       ;need a Wayland compositor
      #:configure-flags
      #~(list "-Dman=false" "-Dgtk_doc=false" "-Dtests=false"
              (string-append "-Dsystemd_user_unit_dir=" #$output
                             "/lib/systemd/user"))
      #:phases
      #~(modify-phases %standard-phases
          ;; Super in the terminal layout's key bar, before stevia's own
          ;; defaults (Sway needs it; author, 2026-10-30).
          ;; Ignore hardware keyboards: the Pro1X keyboard is always
          ;; attached, slid in or not, and stevia stayed disabled for every
          ;; text field (handle_activate, active 1, enabled 0).  Whether to
          ;; offer it is left to screen-keyboard-enabled, which the slider
          ;; helpers set.  Here, not only in pro1x-gsettings-defaults: the
          ;; wrapper puts this package's schemas first in XDG_DATA_DIRS, so
          ;; stevia never saw the profile's override (2026-10-30).
          ;; Compiled here: the schemas were already compiled when this
          ;; phase ran, without it (gsettings with GSETTINGS_SCHEMA_DIR on
          ;; this package read false).
          (add-after 'install 'pro1x-ignore-hw-keyboards
            (lambda _
              (let ((dir (string-append #$output "/share/glib-2.0/schemas")))
                (call-with-output-file
                    (string-append dir "/90_fxtec-pro1x.gschema.override")
                  (lambda (port)
                    (display "[mobi.phosh.osk]\nignore-hw-keyboards=true\n
[mobi.phosh.osk.Terminal]
shortcuts=['<super>', '<ctrl>', '<alt>', 'Left', 'Up', 'Down', 'Right', '<ctrl>r', 'Home', 'End', '<ctrl>w', '<alt>b', '<alt>f', '<ctrl>v', '<ctrl>c', '<ctrl><shift>v', '<ctrl><shift>c', 'Menu']
"
                             port)))
                (invoke "glib-compile-schemas" dir)))))))
    ;; python: tools/write-layout-info.py generates layouts.json.
    (native-inputs (list pkg-config (list glib "bin") gettext-minimal python
                         wayland-protocols))
    ;; hunspell: word completion (meson wants at least one completer).
    (inputs (list dconf elogind feedbackd-0.8 glib gmobile gnome-desktop
                  gsettings-desktop-schemas gtk+ hunspell json-glib libhandy
                  libxkbcommon wayland))
    (home-page "https://gitlab.gnome.org/World/Phosh/stevia")
    (synopsis "On-screen keyboard for Phosh")
    (description
     "Stevia is the on-screen keyboard for the Phosh mobile shell, with word
completion and several layouts.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; pro1x-mms-fetch — MMS with a separate MMS APN (see the script's header)
;;; mmsd-tng downloads only over the active connection with its MMS APN, and
;;; the author's operator refuses a second connection on the MMS APN
;;; (ServiceOptionNotSubscribed, 2026-10-30).  Asks the user, switches the
;;; mobile connection to the MMS APN while mmsd-tng downloads, switches back.
;;; Started by phosh-pro1x-shell.  Source: device/mms/pro1x-mms-fetch.
;;; ---------------------------------------------------------------------------
(define-public pro1x-mms-fetch
  (package
    (name "pro1x-mms-fetch")
    (version "0.1")
    (source (local-file (repository-file "device/mms") "pro1x-mms"
                        #:recursive? #t))
    (build-system copy-build-system)
    (inputs (list bash-minimal coreutils gawk grep libnotify network-manager
                  sed))
    (arguments
     (list
      #:install-plan #~'(("pro1x-mms-fetch" "bin/")
                         ("pro1x-mms-fetch.desktop" "share/applications/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((bin (string-append #$output "/bin/pro1x-mms-fetch")))
                (chmod bin #o755)
                (wrap-program bin
                  `("PATH" ":" prefix
                    ,(map (lambda (p)
                            (string-append (assoc-ref inputs p) "/bin"))
                          '("coreutils" "gawk" "grep" "libnotify"
                            "network-manager" "sed"))))))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Fetch MMS over a separate MMS APN, after asking")
    (description
     "pro1x-mms-fetch switches the mobile connection to the MMS APN while
mmsd-tng downloads waiting MMS, after asking the user, then switches back.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; pro1x-doubletap — wake the panel with a double tap
;;; The touchscreen keeps reporting touches with the panel off; two quick
;;; taps then send a power-key press from a uinput device (as SailfishOS's
;;; mce emulates it).  Run by pro1x-hardware-service-type
;;; (double-tap-wake?).  Source: device/input/pro1x-doubletap.c.
;;; ---------------------------------------------------------------------------
(define-public pro1x-doubletap
  (package
    (name "pro1x-doubletap")
    (version "0.1")
    (source (local-file (repository-file "device/input/pro1x-doubletap.c")
                        "pro1x-doubletap.c"))
    (build-system trivial-build-system)
    (native-inputs
     (list (@ (gnu packages commencement) gcc-toolchain)
           linux-libre-headers))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin (string-append #$output "/bin")))
            (mkdir-p bin)
            (setenv "PATH"
                    (string-append #$(this-package-native-input "gcc-toolchain")
                                   "/bin"))
            (invoke "gcc" "-O2" "-Wall" "-o"
                    (string-append bin "/pro1x-doubletap") #$source
                    (string-append
                     "-I" #$(this-package-native-input "linux-libre-headers")
                     "/include"))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Wake the F(x)tec Pro1X panel with a double tap")
    (description
     "pro1x-doubletap watches the touchscreen while the panel is off and
sends a power-key press when it sees two quick taps close together.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; bluetuith — Bluetooth manager in the terminal, for Sway's quick actions
;;; From the author's guix-private-channel (mlaparie/packages/bluetuith.scm):
;;; upstream's release binary (Go, MIT).  Fixed to the arm64 build here: the
;;; original picks the build from %current-system when the package is
;;; defined, which is the PC's when the PC builds for the phone.
;;; ---------------------------------------------------------------------------
(define-public bluetuith
  (package
    (name "bluetuith")
    (version "0.1.9")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/darkhz/bluetuith/releases/download/v"
                           version "/bluetuith_" version "_Linux_arm64.tar.gz"))
       (sha256
        (base32 "0h1hynihinvrpf1l67d5yxhrfhiq3x4xi84f3fzfcbwndd7lfsl9"))))
    (supported-systems '("aarch64-linux"))
    (build-system binary-build-system)
    (arguments
     (list
      #:install-plan #~'(("bluetuith" "bin/"))
      #:strip-binaries? #t))
    (inputs (list bluez))
    (home-page "https://github.com/darkhz/bluetuith")
    (synopsis "Bluetooth manager in the terminal")
    (description "bluetuith manages Bluetooth adapters and devices from a
terminal interface.")
    (license license:expat)))

;;; ---------------------------------------------------------------------------
;;; pro1x-wallpapers — the Sway and Phosh backgrounds, made for the port
;;;   light.png  a low-poly gradient (coral, plum, deep teal), generated
;;;   dark.png   Guix's gnu (guix-backgrounds, CC-BY-SA 4.0), lilac on slate
;;; Square 2160x2160, so they fill the panel in portrait and landscape.
;;; Generated by device/wallpapers/make-wallpapers.py (fixed seed), rendered
;;; with rsvg-convert, composed with ImageMagick: PNGs, since the image
;;; loaders here did not take SVG backgrounds.
;;; ---------------------------------------------------------------------------
(define-public pro1x-wallpapers
  (package
    (name "pro1x-wallpapers")
    (version "0.1")
    (source (local-file (repository-file "device/wallpapers") "pro1x-wallpapers"
                        #:recursive? #t))
    (build-system trivial-build-system)
    (native-inputs (list guix-backgrounds imagemagick librsvg python-minimal))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((dir (string-append #$output "/share/backgrounds/pro1x"))
                (disc (string-append #$(this-package-native-input
                                        "guix-backgrounds")
                                     "/share/backgrounds/guix/"
                                     "guix-disc-flat-16-9.svg")))
            (setenv "PATH"
                    (string-join
                     (map (lambda (p) (string-append p "/bin"))
                          (list #$(this-package-native-input "librsvg")
                                #$(this-package-native-input "imagemagick")
                                #$(this-package-native-input "python-minimal")))
                     ":"))
            (mkdir-p dir)
            (invoke "python3" (string-append #$source "/make-wallpapers.py")
                    disc ".")
            (invoke "rsvg-convert" "light.svg"
                    "-o" (string-append dir "/light.png"))
            (invoke "rsvg-convert" "-w" "3840" "gnu.svg" "-o" "gnu-wide.png")
            (invoke "convert" "gnu-wide.png" "-trim" "+repage"
                    "-resize" "520x520" "gnu.png")
            ;; A little above the middle.
            (invoke "convert" "-size" "2160x2160" "xc:#252a3a" "gnu.png"
                    "-gravity" "center" "-geometry" "+0-90" "-composite"
                    (string-append dir "/dark.png"))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Background images for the F(x)tec Pro1X sessions")
    (description "A low-poly gradient and Guix's gnu on slate, as square
PNGs for the light and dark Sway and Phosh backgrounds.")
    (license (list license:gpl3+          ;the generator, light.png
                   license:cc-by-sa4.0)))) ;dark.png, after Guix's artwork

;;; ---------------------------------------------------------------------------
;;; pro1x-gsettings-defaults — system-wide GSettings defaults
;;; An override in the system profile's share/glib-2.0/schemas, which Guix's
;;; glib-schemas profile hook compiles together with every schema there (an
;;; override in phosh-pro1x's own directory only reaches Phosh's schemas).
;;;   - sound above 100%: the speaker is quiet even at full gain (author,
;;;     2026-10-29); GNOME's slider then goes to 150%, Sway's keys stop at 120%.
;;;   - stevia ignores hardware keyboards: the Pro1X keyboard is always
;;;     attached, slid in or not, and stevia stayed disabled for every text
;;;     field.  Whether to offer the on-screen keyboard is left to
;;;     screen-keyboard-enabled, which phosh-pro1x-slider sets from the
;;;     slider (on while slid in, off while out).  Tested by hand on the
;;;     phone, 2026-10-30: stevia came up on a text field in Phosh.
;;; ---------------------------------------------------------------------------
(define-public pro1x-gsettings-defaults
  (package
    (name "pro1x-gsettings-defaults")
    (version "0.1")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((dir (string-append #$output "/share/glib-2.0/schemas")))
            (mkdir-p dir)
            (call-with-output-file
                (string-append dir "/91_pro1x-defaults.gschema.override")
              (lambda (port)
                (display "[org.gnome.desktop.sound]
allow-volume-above-100-percent=true

[mobi.phosh.osk]
ignore-hw-keyboards=true
" port)))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "GSettings defaults for the F(x)tec Pro1X")
    (description
     "System-wide GSettings overrides for the Pro1X: volume above 100%, an
on-screen keyboard despite the always-attached hardware keyboard.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; libadwaita-1.9 — for phosh-mobile-settings only
;;; Guix ships 1.8.4; phosh-mobile-settings 0.56 uses AdwSidebar and the
;;; view-stack section API, new in 1.9.  Same dependencies as 1.8.4.  Built
;;; without documentation, introspection, Vala bindings and tests to keep
;;; the aarch64 build short; nothing else in the system links against it.
;;; ---------------------------------------------------------------------------
(define libadwaita-1.9
  (package
    (inherit libadwaita)
    (version "1.9.4")
    (source
     (origin
       (inherit (package-source libadwaita))
       (uri (string-append "mirror://gnome/sources/libadwaita/"
                           (version-major+minor version) "/"
                           "libadwaita-" version ".tar.xz"))
       (sha256
        (base32 "1vk287x2ph83fxil36sx2a6hxllwg0hnhvgrrn9w4gblxr9k9azm"))))
    (outputs '("out"))
    (arguments
     (list #:tests? #f
           #:configure-flags
           #~(list "-Ddocumentation=false"
                   "-Dintrospection=disabled"
                   "-Dvapi=false"
                   "-Dtests=false"
                   "-Dexamples=false")))))

;;; libcellbroadcast, a meson subproject of phosh-mobile-settings (static,
;;; library only).  Its own gvdb subproject is phoc-gvdb-source (same commit).
(define phosh-mobile-settings-libcellbroadcast-source
  (origin
    (method url-fetch)
    (uri "https://gitlab.freedesktop.org/devrtz/cellbroadcastd/-/archive/v0.0.2/cellbroadcastd-v0.0.2.tar.gz")
    (sha256
     (base32 "0867prrjk2515jrmcjg1jv9ci6xamgz1vslvvdlhnbi6h587vfmy"))))

;;; ---------------------------------------------------------------------------
;;; phosh-mobile-settings — Phosh's own settings app
;;; Phosh's top-panel gear opens it (launch-mobile-panel); without it the gear
;;; does nothing.  Not in Guix.  Needs libadwaita >= 1.9 (above); asks for
;;; polkit-gobject >= 126 but only calls polkit_permission_new_sync, so the
;;; check is relaxed to Guix's polkit 121.  gvc, libcellbroadcast and gvdb
;;; are pre-seeded meson subprojects (no network in the build).
;;; ---------------------------------------------------------------------------
(define-public phosh-mobile-settings
  (package
    (name "phosh-mobile-settings")
    (version "0.56.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://gitlab.gnome.org/World/Phosh/phosh-mobile-settings/-/archive/v"
             version "/phosh-mobile-settings-v" version ".tar.gz"))
       (sha256
        (base32 "1v03y518wv6b1zaz59fnnd1i56hhk25y9hr3x62q4xdkv68c043n"))))
    (build-system meson-build-system)
    (native-inputs
     (list pkg-config
           `(,glib "bin")
           `(,gtk "bin")                ; gtk-update-icon-cache
           gettext-minimal
           desktop-file-utils
           wayland))                    ; wayland-scanner
    (inputs
     (list accountsservice
           feedbackd-0.8
           glib
           gmobile-0.7
           gnome-desktop
           gsound
           gst-plugins-base
           gst-plugins-good
           gtk
           json-glib
           libadwaita-1.9
           libportal
           libyaml
           `(,lm-sensors "lib")         ; librem5 plugin
           mobile-broadband-provider-info
           modem-manager-1.24
           phosh-pro1x                  ; phosh-plugins.pc, phosh-settings.pc
           polkit
           pulseaudio                   ; gvc
           wayland
           wayland-protocols))
    (arguments
     (list #:tests? #f
           #:glib-or-gtk? #t
           #:configure-flags
           ;; Guix runs meson with --wrap-mode=nofallback; libcellbroadcast
           ;; is only reachable as a fallback subproject.
           #~(list "-Dintrospection=false"
                   "--force-fallback-for=libcellbroadcast-0.0")
           #:phases
           #~(modify-phases %standard-phases
               (add-after 'unpack 'seed-subprojects
                 (lambda _
                   (for-each
                    (lambda (dir source)
                      (mkdir-p (string-append "subprojects/" dir))
                      (invoke "tar" "xf" source "--strip-components=1"
                              "-C" (string-append "subprojects/" dir)))
                    '("gvc" "libcellbroadcast" "gvdb")
                    (list #$phosh-gvc-source
                          #$phosh-mobile-settings-libcellbroadcast-source
                          #$phoc-gvdb-source))))
               (add-after 'unpack 'relax-polkit-version
                 (lambda _
                   (substitute* "meson.build"
                     (("'polkit-gobject-1', version: '>= 126'")
                      "'polkit-gobject-1', version: '>= 121'"))))
               ;; gtk4's GStreamer media backend aborts the app without
               ;; playbin3 ("GstPlay: 'playbin3' element not found").
               (add-after 'glib-or-gtk-wrap 'wrap-gstreamer
                 (lambda _
                   (wrap-program (string-append #$output
                                                "/bin/phosh-mobile-settings")
                     `("GST_PLUGIN_SYSTEM_PATH" prefix
                       (,(string-append #$(this-package-input "gst-plugins-base")
                                        "/lib/gstreamer-1.0")
                        ,(string-append #$(this-package-input "gst-plugins-good")
                                        "/lib/gstreamer-1.0")))))))))
    (home-page "https://gitlab.gnome.org/World/Phosh/phosh-mobile-settings")
    (synopsis "Settings app for the Phosh mobile shell")
    (description
     "Phosh Mobile Settings configures what GNOME Settings does not cover in
Phosh: lock screen and its plugins, app filtering, feedback, on-screen
keyboard, sensors and cell broadcast alerts.")
    (license license:gpl3+)))

;;; ---------------------------------------------------------------------------
;;; sway-launcher-desktop — fzf launcher for .desktop entries and commands
;;; Run in a floating terminal from the sway config (Super+d).  The script's
;;; awk uses BEGINFILE, so it needs gawk; it is wrapped with fzf, gawk, sed,
;;; coreutils and util-linux (setsid) on PATH.
;;; ---------------------------------------------------------------------------
(define-public sway-launcher-desktop
  (package
    (name "sway-launcher-desktop")
    (version "unstable-f19bbb8")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/Biont/sway-launcher-desktop/archive/"
             "f19bbb8795567d54005356357562c748ea33a7a9.tar.gz"))
       (sha256
        (base32 "1md718draf7nn3f2xr9qnynvvk6cdg11xggrspvzp0pws34fjxka"))
       ;; Preview shows the .desktop file and the executable (mlaparie).
       (patches
        (list (local-file
               (repository-file "device/sway/sway-launcher-desktop-preview.patch"))))))
    (build-system copy-build-system)
    (inputs (list bash coreutils fzf gawk sed util-linux))
    (arguments
     (list
      #:install-plan
      #~'(("sway-launcher-desktop.sh" "bin/sway-launcher-desktop"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((bin (string-append #$output "/bin/sway-launcher-desktop")))
                (chmod bin #o755)
                (wrap-program bin
                  `("PATH" ":" prefix
                    ,(map (lambda (p)
                            (string-append (assoc-ref inputs p) "/bin"))
                          '("coreutils" "fzf" "gawk" "sed" "util-linux"))))))))))
    (home-page "https://github.com/Biont/sway-launcher-desktop")
    (synopsis "Terminal application launcher for sway, using fzf")
    (description
     "sway-launcher-desktop lists desktop entries and commands on PATH in fzf
and launches the selected one.  It is meant to run in a floating terminal
window opened by a sway key binding.")
    (license license:gpl3)))

;;; ---------------------------------------------------------------------------
;;; pro1x-sway-config — sway defaults for the Pro1X, from device/sway/
;;;   share/pro1x-sway/config              ~/.config/sway/config (skeleton)
;;;   share/pro1x-sway/i3status-rust.toml  ~/.config/i3status-rust/config.toml
;;;                                        (skeleton)
;;;   bin/sway-window-switcher           fzf window switcher (Super+Tab)
;;;   bin/sway-autorotate                rotation from iio-sensor-proxy
;;;   bin/sway-quick-actions            Phosh-like toggles in fzf (Super+q)
;;;   bin/sway-notifications             mako's notifications for its dock
;;;   bin/pro1x-osk-slider               no on-screen keyboard while slid out
;;;   bin/pro1x-lock                     swaylock with a banner and notifications
;;;   bin/pro1x-mako                     mako, logging notification arrivals
;;;   bin/pro1x-notify                   on a notification: log, wake, relock
;;;   bin/pro1x-gestures                 edge swipes on the touchscreen (lisgd)
;;;   bin/pro1x-term                     footclient, or foot without the server
;;;   bin/pro1x-call-watch               unlock for an incoming call, relock after
;;;   bin/pro1x-status                   status texts for the i3status-rust bar
;;;   bin/pro1x-screenshot               screenshots (grim, slurp)
;;;   bin/pro1x-portrait-apps            portrait while Snapshot or Calls is focused
;;;   bin/pro1x-menu                     resident menus, toggled from the scratchpad
;;;   bin/pro1x-switcher                 the window switcher (fzf)
;;;   bin/pro1x-wifi                     Wi-Fi picker (the author's nmcli-fzf)
;;;   bin/pro1x-blank-led                dim white LED while blank, not locked
;;;   bin/pro1x-camera                   camera button: open, focus or shoot Snapshot
;;; ---------------------------------------------------------------------------
(define-public pro1x-sway-config
  (package
    (name "pro1x-sway-config")
    (version "0.1")
    (source (local-file (repository-file "device/sway") "pro1x-sway"
                        #:recursive? #t))
    (build-system copy-build-system)
    (inputs (list bash coreutils curl evtest font-dejavu foot fzf gawk grep
                  grim guile-3.0 imagemagick jq lisgd procps sed slurp swayidle
                  wl-clipboard (list glib "bin")))
    (arguments
     (list
      #:install-plan
      #~'(("config" "share/pro1x-sway/")
          ("pro1x.conf" "share/pro1x-sway/")
          ("i3status-rust.toml" "share/pro1x-sway/")
          ("foot.ini" "share/pro1x-sway/")
          ("sway-window-switcher" "bin/")
          ("pro1x-dim" "bin/")
          ("pro1x-idle" "bin/")
          ("sway-autorotate" "bin/")
          ("sway-quick-actions" "bin/")
          ("sway-notifications" "bin/")
          ("pro1x-osk-slider" "bin/")
          ("pro1x-lock" "bin/")
          ("pro1x-mako" "bin/")
          ("pro1x-notify" "bin/")
          ("pro1x-gestures" "bin/")
          ("pro1x-term" "bin/")
          ("pro1x-call-watch" "bin/")
          ("pro1x-status" "bin/")
          ("pro1x-screenshot" "bin/")
          ("pro1x-portrait-apps" "bin/")
          ("pro1x-menu" "bin/")
          ("pro1x-switcher" "bin/")
          ("pro1x-wifi" "bin/")
          ("pro1x-blank-led" "bin/")
          ("pro1x-camera" "bin/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((bin (string-append #$output "/bin/sway-window-switcher"))
                    (dim (string-append #$output "/bin/pro1x-dim")))
                (chmod bin #o755)
                (wrap-program bin
                  `("PATH" ":" prefix
                    (,(string-append #$output "/bin")   ;pro1x-term
                     ,@(map (lambda (p)
                              (string-append (assoc-ref inputs p) "/bin"))
                            '("coreutils" "foot" "fzf" "jq")))))
                (chmod dim #o755)
                (wrap-program dim
                  `("PATH" ":" prefix
                    (,(string-append (assoc-ref inputs "coreutils")
                                     "/bin"))))
                (let ((idle (string-append #$output "/bin/pro1x-idle")))
                  (chmod idle #o755)
                  (wrap-program idle
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,(string-append (assoc-ref inputs "swayidle") "/bin")
                       ,(string-append (assoc-ref inputs "glib") "/bin")
                       ,(string-append (assoc-ref inputs "coreutils")
                                       "/bin")))))
                ;; monitor-sensor and swaymsg come from the system profile.
                (let ((rot (string-append #$output "/bin/sway-autorotate")))
                  (chmod rot #o755)
                  (wrap-program rot
                    `("PATH" ":" prefix
                      ,(map (lambda (p)
                              (string-append (assoc-ref inputs p) "/bin"))
                            '("coreutils" "evtest" "jq" "sed")))))
                (let ((qs (string-append #$output "/bin/sway-quick-actions")))
                  (chmod qs #o755)
                  (wrap-program qs
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "curl" "evtest" "foot" "fzf"
                                "gawk" "glib" "grep" "jq" "procps" "sed"))))))
                (let ((lock (string-append #$output "/bin/pro1x-lock")))
                  (chmod lock #o755)
                  (wrap-program lock
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "gawk" "imagemagick" "jq" "procps"
                                "sed"))))
                    `("PRO1X_LOCK_FONT" =
                      (,(string-append (assoc-ref inputs "font-dejavu")
                                       "/share/fonts/truetype/DejaVuSansMono.ttf")))))
                (for-each
                 (lambda (name)
                   (let ((f (string-append #$output "/bin/" name)))
                     (chmod f #o755)
                     ;; swaymsg, foot and sway-launcher-desktop come from
                     ;; the system profile.
                     (wrap-program f
                       `("PATH" ":" prefix
                         (,(string-append #$output "/bin")
                          ,@(map (lambda (p)
                                   (string-append (assoc-ref inputs p) "/bin"))
                                 '("coreutils" "curl" "fzf" "jq" "procps"
                                   "glib")))))))
                 '("pro1x-menu" "pro1x-switcher" "pro1x-wifi" "pro1x-blank-led"
                   "pro1x-camera"))
                (let ((pa (string-append #$output "/bin/pro1x-portrait-apps")))
                  (chmod pa #o755)
                  (wrap-program pa
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "evtest" "jq"))))))
                (let ((sc (string-append #$output "/bin/pro1x-screenshot")))
                  (chmod sc #o755)
                  (wrap-program sc
                    `("PATH" ":" prefix
                      ,(map (lambda (p)
                              (string-append (assoc-ref inputs p) "/bin"))
                            '("coreutils" "glib" "grim" "slurp" "wl-clipboard")))))
                (let ((st (string-append #$output "/bin/pro1x-status")))
                  (chmod st #o755)
                  ;; mmcli and rfkill come from the system profile.
                  (wrap-program st
                    `("PATH" ":" prefix
                      ,(map (lambda (p)
                              (string-append (assoc-ref inputs p) "/bin"))
                            '("coreutils" "grep" "sed")))))
                (let ((cw (string-append #$output "/bin/pro1x-call-watch")))
                  (chmod cw #o755)
                  ;; swaymsg from the system profile.
                  (wrap-program cw
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "glib" "grep" "procps" "sed"))))))
                (let ((term (string-append #$output "/bin/pro1x-term")))
                  (chmod term #o755)
                  (wrap-program term
                    `("PATH" ":" prefix
                      (,(string-append (assoc-ref inputs "foot") "/bin")))))
                (let ((g (string-append #$output "/bin/pro1x-gestures")))
                  (chmod g #o755)
                  ;; swaymsg, foot and the menus: system profile and $output.
                  (wrap-program g
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "grep" "jq" "lisgd"))))))
                (let ((notify (string-append #$output "/bin/pro1x-notify")))
                  (chmod notify #o755)
                  ;; swaymsg comes from the system profile.
                  (wrap-program notify
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,@(map (lambda (p)
                                (string-append (assoc-ref inputs p) "/bin"))
                              '("coreutils" "jq" "procps" "swayidle"))))))
                (let ((mako (string-append #$output "/bin/pro1x-mako")))
                  (chmod mako #o755)
                  ;; sway-notifications for on-notify; mako from the system.
                  (wrap-program mako
                    `("PATH" ":" prefix
                      (,(string-append #$output "/bin")
                       ,(string-append (assoc-ref inputs "coreutils") "/bin")))))
                (let ((o (string-append #$output "/bin/pro1x-osk-slider")))
                  (chmod o #o755)
                  (wrap-program o
                    `("PATH" ":" prefix
                      ,(map (lambda (p)
                              (string-append (assoc-ref inputs p) "/bin"))
                            '("coreutils" "evtest" "glib")))))
                (let ((n (string-append #$output "/bin/sway-notifications")))
                  (chmod n #o755)
                  (wrap-program n
                    `("PATH" ":" prefix
                      (,(string-append (assoc-ref inputs "glib") "/bin")))))))))))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Sway defaults for the F(x)tec Pro1X")
    (description
     "Default sway configuration for the Pro1X in landscape with the keyboard
out, the device settings every sway session shares (pro1x.conf, for
/etc/sway/config.d), an i3status-rust bar configuration, an fzf window
switcher, and pro1x-idle and pro1x-dim, which dim the panel when idle.")
    (license license:gpl3+)))
