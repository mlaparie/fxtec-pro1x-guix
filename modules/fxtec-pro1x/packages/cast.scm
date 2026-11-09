;;; fxtec-pro1x/packages/cast.scm — casting to a Chromecast or a Miracast display.
;;;
;;; catt sends a URL or a file, which the receiver then plays by itself.
;;; GNOME Network Displays mirrors the screen.

(define-module (fxtec-pro1x packages cast)
  #:use-module (gnu packages avahi)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages protobuf)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-web)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages video)
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
        (base32 "11gdj4bdgpdrvnsa858pxk8lg2wrx267p1784pvypir2r0dlmkhy"))))
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
