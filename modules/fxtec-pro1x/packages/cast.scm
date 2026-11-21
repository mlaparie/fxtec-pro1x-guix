;;; fxtec-pro1x/packages/cast.scm — casting to a Chromecast or a Miracast display.
;;;
;;; catt sends a URL or a file, which the receiver then plays by itself.
;;; GNOME Network Displays mirrors the screen.

(define-module (fxtec-pro1x packages cast)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages avahi)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages networking)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages protobuf)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-web)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages video)
  #:use-module ((gnu packages window-management) #:select (wl-mirror))
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix build-system pyproject)
  #:use-module (guix build-system python)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define-public python-casttube
  (package
    (name "python-casttube")
    (version "0.2.1")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "casttube" version))
       (sha256
        (base32 "10pw2sjy648pvp42lbbdmkkx79bqlkq1xcbzp1frraj9g66azljl"))))
    (build-system pyproject-build-system)
    (arguments (list #:tests? #f))
    (native-inputs (list python-setuptools python-wheel))
    (propagated-inputs (list python-requests))
    (home-page "https://github.com/ur1katz/casttube")
    (synopsis "Control YouTube on a Chromecast")
    (description "This package lets a program queue and play YouTube videos
on a Chromecast through YouTube's own receiver application.")
    (license license:expat)))

;; PyChromecast needs a newer one than Guix has.
(define-public python-zeroconf-0.148
  (package
    (inherit python-zeroconf)
    (version "0.148.0")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "zeroconf" version))
       (sha256
        (base32 "00hpd1phacfz99yinq9p6qqmyq1g7ml2s4a5v4ijwrgk7l9cmz03"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          ;; The Cython modules only speed it up, and take long to build.
          (add-before 'build 'skip-cython
            (lambda _ (setenv "SKIP_CYTHON" "1"))))))
    (native-inputs (list python-poetry-core python-setuptools))
    (propagated-inputs (list python-ifaddr))))

(define-public python-pychromecast
  (package
    (name "python-pychromecast")
    (version "14.1.1")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "pychromecast" version))
       (sha256
        (base32 "0rrwls3l0lcscnk0wnikn4dwfrfi1p9mlyya8v0pn068f0vmaxcv"))))
    (build-system pyproject-build-system)
    (arguments (list #:tests? #f))
    (native-inputs (list python-setuptools python-wheel))
    (propagated-inputs
     (list python-casttube python-protobuf-5 python-zeroconf-0.148))
    (home-page "https://github.com/home-assistant-libs/pychromecast")
    (synopsis "Control a Chromecast from Python")
    (description "This package finds Chromecast devices on the local network
and controls what they play.")
    (license license:expat)))

(define-public catt
  (package
    (name "catt")
    (version "0.13.3")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "catt" version))
       (sha256
        (base32 "0xv5kcflzkglhlyfb31szm01sq7p6f45vpy7vi1ra0nvvg6mj9h1"))))
    (build-system pyproject-build-system)
    (arguments (list #:tests? #f))
    (native-inputs (list python-poetry-core))
    (propagated-inputs
     (list python-click python-ifaddr python-pychromecast python-requests
           yt-dlp))
    (home-page "https://github.com/skorokithakis/catt")
    (synopsis "Cast URLs and local files to a Chromecast")
    (description "@command{catt} sends a video from any site yt-dlp supports,
or a local file, to a Chromecast, and controls its playback.")
    (license license:bsd-2)))

(define-public gnome-network-displays
  (package
    (name "gnome-network-displays")
    (version "0.99.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "mirror://gnome/sources/gnome-network-displays/"
                           (version-major+minor version)
                           "/gnome-network-displays-" version ".tar.xz"))
       (sha256
        (base32 "11gdj4bdgpdrvnsa858pxk8lg2wrx267p1784pvypir2r0dlmkhy"))
       ;; Miracast on the phone's hardware encoder (Venus) instead of x264
       ;; on the CPU, too slow for a smooth 1080p picture (author).
       (patches
        (list
         (local-file
          (repository-file "device/patches/gnome-network-displays-v4l2h264enc.patch")
          "gnome-network-displays-v4l2h264enc.patch")))))
    (build-system meson-build-system)
    (arguments
     (list
      #:glib-or-gtk? #t
      #:tests? #f
      #:configure-flags
      #~(list "-Dfirewalld_zone=false" "-Dbuild_daemon=false")
      #:phases
      #~(modify-phases %standard-phases
          ;; It builds its GStreamer pipelines at run time.
          (add-after 'install 'wrap-gstreamer
            (lambda* (#:key inputs #:allow-other-keys)
              (wrap-program
                  (string-append #$output "/bin/gnome-network-displays")
                `("GST_PLUGIN_SYSTEM_PATH" ":" prefix
                  ,(map (lambda (p)
                          (string-append (assoc-ref inputs p)
                                         "/lib/gstreamer-1.0"))
                        '("gstreamer" "gst-plugins-base" "gst-plugins-good"
                          "gst-plugins-bad" "gst-plugins-ugly" "gst-libav"
                          "gst-rtsp-server" "pipewire")))))))))
    (native-inputs
     (list desktop-file-utils gettext-minimal (list glib "bin") (list gtk "bin")
           pkg-config protobuf-c))
    (inputs
     (list avahi glib gst-libav gst-plugins-bad gst-plugins-base
           gst-plugins-good gst-plugins-ugly gst-rtsp-server gstreamer gtk
           json-glib libadwaita libportal libsoup network-manager pipewire
           protobuf-c pulseaudio))
    (home-page "https://gitlab.gnome.org/GNOME/gnome-network-displays")
    (synopsis "Mirror the screen to a Miracast or Chromecast display")
    (description "GNOME Network Displays streams the desktop to Miracast and
Chromecast receivers.")
    (license license:gpl3+)))

;; The screen to H.264 with no CPU copy (device/stream/pro1x-screencast.c):
;; Sway's copy of the output, turned, scaled and converted to NV12 by the GPU
;; in Venus's own buffers, encoded by Venus.  pro1x-stream-webrtc uses it
;; when it is found.  State: run on the phone 2026-11-20 (4% of a core,
;; 32-69 ms from Sway's frame to the encoded one).
(define-public pro1x-screencast
  (package
    (name "pro1x-screencast")
    (version "0.1")
    (source (local-file (repository-file "device/stream") "pro1x-screencast"
                        #:recursive? #t))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f
           #:phases
           #~(modify-phases %standard-phases
               (delete 'configure)
               (replace 'build
                 (lambda _
                   (setenv "CC" #$(cc-for-target))
                   (invoke "sh" "build.sh")))
               (replace 'install
                 (lambda _
                   (install-file "pro1x-screencast"
                                 (string-append #$output "/bin")))))))
    (native-inputs (list pkg-config wayland wayland-protocols wlr-protocols))
    (inputs (list libdrm mesa wayland))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Encode a Wayland output to H.264 without CPU copies")
    (description "pro1x-screencast captures a wlroots output with
wlr-screencopy into DMA-BUFs, has the GPU convert each frame to NV12 straight
into the V4L2 encoder's own buffers, and writes the H.264 access units to its
standard output, framed with their capture times.")
    (license license:agpl3+)))

;; Stream's WebRTC method (device/sway/pro1x-stream-webrtc).  Its own package:
;; GStreamer's Python typelibs and plugins are found through its wrapper.
(define-public pro1x-stream-webrtc
  (package
    (name "pro1x-stream-webrtc")
    (version "0.1")
    (source (local-file (repository-file "device/sway/pro1x-stream-webrtc")))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan ''(("pro1x-stream-webrtc" "bin/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((bin (string-append #$output "/bin/pro1x-stream-webrtc"))
                    (in (lambda (dir names)
                          (map (lambda (p)
                                 (string-append (assoc-ref inputs p) dir))
                               names))))
                (chmod bin #o755)
                (patch-shebang bin (list (string-append
                                          (assoc-ref inputs "python") "/bin")))
                (wrap-program bin
                  `("GUIX_PYTHONPATH" prefix (,(getenv "GUIX_PYTHONPATH")))
                  `("GI_TYPELIB_PATH" ":" prefix
                    ,(in "/lib/girepository-1.0"
                         '("glib" "gobject-introspection" "gstreamer"
                           "gst-plugins-base" "gst-plugins-bad")))
                  ;; pipewiresrc and pw-dump, for the ScreenCast portal.
                  `("GST_PLUGIN_SYSTEM_PATH" ":" prefix
                    ,(in "/lib/gstreamer-1.0"
                         '("gstreamer" "gst-plugins-base" "gst-plugins-good"
                           "gst-plugins-bad" "libnice" "pipewire")))
                  ;; wl-mirror: the stream's own output on the panel too;
                  ;; openssl: its HTTPS certificate.
                  `("PATH" ":" suffix
                    ,(in "/bin" '("pipewire" "wl-mirror" "openssl"
                                  "pro1x-screencast"))))))))))
    (inputs
     (list glib gobject-introspection gst-plugins-bad gst-plugins-base
           gst-plugins-good gstreamer libnice pipewire python python-evdev
           python-pygobject wl-mirror openssl pro1x-screencast))
    (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
    (synopsis "Serve an H.264 stream to a browser by WebRTC")
    (description "This package serves a web page, and sends the H.264 video of
a command to the browser that opens it, by WebRTC.  With --interactive, the
page's touches and keys are played on the device by virtual input devices.")
    (license license:agpl3+)))
