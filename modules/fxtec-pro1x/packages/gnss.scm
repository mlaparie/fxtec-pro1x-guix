;;; fxtec-pro1x/packages/gnss.scm — a GPS app for the phone
;;;
;;; Satellite (tpikonen) shows the satellites, signal, fix, speed and a
;;; track, from the modem's NMEA through ModemManager; postmarketOS ships
;;; it, Guix has no GPS app.  It needs no geoclue, so it also shows whether
;;; the modem's GNSS sends anything at all (pro1x-gnss-unlock in
;;; services/modem.scm).
;;;
;;; ModemManager's typelib comes from Guix's modem-manager (1.22): the port's
;;; 1.24 is built without introspection.  Satellite only uses libmm-glib's
;;; D-Bus client, against the 1.24 daemon.
;;;
;;; State: build-tested only.

(define-module (fxtec-pro1x packages gnss)
  #:use-module (gnu packages check)
  #:use-module (gnu packages freedesktop) ; modem-manager (Guix's, 1.22)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)       ; libadwaita
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-xyz)
  #:use-module (guix build-system pyproject)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages))

(define-public python-pynmea2
  (package
    (name "python-pynmea2")
    (version "1.19.0")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "pynmea2" version))
       (sha256
        (base32 "0z0djzya5x5hkac4dkiq85b489p3g5fcrr9mqb8qgy3r6awpkahx"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          ;; setup.py reads the version with the imp module, gone in
          ;; Python 3.12.  (Its lines end in CRLF.)
          (add-after 'unpack 'drop-imp
            (lambda _
              (substitute* "setup.py"
                (("^import imp") "")
                (("^_version = imp\\.load_source[^\r\n]*") "")
                (("_version\\.__version__") (string-append "'" #$version "'"))))))))
    (native-inputs (list python-pytest python-setuptools python-wheel))
    (home-page "https://github.com/Knio/pynmea2")
    (synopsis "Python library for the NMEA 0183 protocol")
    (description
     "pynmea2 parses and generates NMEA 0183 sentences, the text protocol of
GPS receivers.")
    (license license:expat)))

(define-public satellite
  (package
    (name "satellite")
    (version "0.9.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/tpikonen/satellite")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1ln248vqmjxiwldb2kyvpx97crqw1bcqrzahgjdz1cl9rb3cprhf"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:tests? #f                       ;no test suite
      #:phases
      #~(modify-phases %standard-phases
          ;; The desktop entry, icon and AppStream file are not part of the
          ;; Python package.
          (add-after 'install 'install-data
            (lambda _
              (install-file "data/satellite.desktop"
                            (string-append #$output "/share/applications"))
              (install-file "data/page.codeberg.tpikonen.satellite.svg"
                            (string-append #$output
                                           "/share/icons/hicolor/scalable/apps"))
              (install-file "data/page.codeberg.tpikonen.satellite.appdata.xml"
                            (string-append #$output "/share/metainfo"))))
          (add-after 'wrap 'wrap-typelibs
            (lambda _
              (wrap-program (string-append #$output "/bin/satellite")
                `("GI_TYPELIB_PATH" ":" prefix
                  (,(getenv "GI_TYPELIB_PATH")))))))))
    (native-inputs (list gobject-introspection python-setuptools python-wheel))
    (inputs (list gtk libadwaita modem-manager python-gpxpy python-pygobject
                  python-pynmea2))
    (home-page "https://codeberg.org/tpikonen/satellite")
    (synopsis "Navigation satellite (GPS/GNSS) information")
    (description
     "Satellite shows the data of navigation satellites received by a modem
through ModemManager: satellites in view and their signal, position, speed
and heading.  It can record a track as GPX.  Its layout adapts to phones.")
    (license license:gpl3)))
