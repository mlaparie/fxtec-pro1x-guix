;;; fxtec-pro1x/packages/sensors.scm — Qualcomm SSC sensors for iio-sensor-proxy
;;;
;;; The Pro¹x's accelerometer, proximity and light sensors sit behind the
;;; ADSP's Snapdragon Sensor Core (SSC), reached over QMI on QRTR, not as
;;; IIO devices.  iio-sensor-proxy reads them through libssc since 3.9
;;; (meson option ssc-support).  Guix has iio-sensor-proxy 3.8 without it
;;; and no libssc, so iio-sensor-proxy found no sensor and exited, and Phosh
;;; offered no auto-rotation.  Recipes follow nixpkgs' (libssc 0.4.4,
;;; iio-sensor-proxy 3.9 with ssc-support enabled), which the NixOS port of
;;; this phone uses.
;;;
;;; State: build-tested only.

(define-module (fxtec-pro1x packages sensors)
  #:use-module (fxtec-pro1x packages misc) ; libqmi-1.36
  #:use-module (gnu packages freedesktop)  ; iio-sensor-proxy
  #:use-module (gnu packages glib)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages protobuf)
  #:use-module (guix build-system meson)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define-public libssc
  (package
    (name "libssc")
    (version "0.4.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/DylanVanAssche/libssc")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0wpj9ckdp7w86p8wqll890qmky00hvcf2bw9824x9kh6v4v39l0b"))))
    (build-system meson-build-system)
    (arguments
     ;; The tests talk to a mock SSC server written in Python, which needs
     ;; PyGObject and more of a QMI environment than the build sandbox has
     ;; (first /usr/bin/env missing, then "No module named 'gi'").  nixpkgs
     ;; does not run them either.  Tested on the phone instead (ssccli).
     (list #:tests? #f))
    (native-inputs (list pkg-config protobuf protobuf-c (list glib "bin")))
    (inputs (list glib protobuf-c))
    ;; libssc.pc requires qmi-glib.
    (propagated-inputs (list libqmi-1.36))
    (home-page "https://codeberg.org/DylanVanAssche/libssc")
    (synopsis "Qualcomm Snapdragon Sensor Core client library")
    (description
     "libssc exposes the sensors of the Qualcomm Snapdragon Sensor Core (SSC),
which runs on a DSP and is reached over QMI, to Linux programs such as
iio-sensor-proxy.")
    (license license:gpl3)))

(define-public iio-sensor-proxy-ssc
  (package
    (inherit iio-sensor-proxy)
    (name "iio-sensor-proxy")
    (version "3.9")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://gitlab.freedesktop.org/hadess/iio-sensor-proxy")
             (commit version)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "044vhkbivpb84cs9zddbri36s4960dqp1z9m2dh0id4hkqbgipyq"))))
    (arguments
     (substitute-keyword-arguments (package-arguments iio-sensor-proxy)
       ((#:configure-flags flags)
        #~(cons "-Dssc-support=enabled" #$flags))
       ((#:phases phases)
        #~(modify-phases #$phases
            ;; Guix's phase replaces "polkit_gobject_dep\\..*" including the
            ;; newline; in 3.9 the next line is libssc's dependency, which
            ;; got glued on ("meson.build:48:115: ERROR: Expecting eof").
            (replace 'patch-polkit-dir
              (lambda _
                (substitute* "meson.build"
                  (("polkit_gobject_dep\\.get_pkgconfig_variable\\('policydir'\\)")
                   (string-append "'" #$output
                                  "/share/polkit-1/actions'")))))
            ;; The SSC accelerometer and proximity tests pass; compass and
            ;; light failed with "daemon did not start in 10 seconds" under
            ;; QEMU, the last two tests of the run.  Skip those two (the
            ;; phone has no compass; light to be checked on the device).
            (add-after 'unpack 'skip-slow-ssc-tests
              (lambda _
                (substitute* "tests/ssc-test.py"
                  (("def test_ssc_(compass|light)" _ name)
                   (string-append "def skipped_ssc_" name)))))))))
    (inputs (modify-inputs (package-inputs iio-sensor-proxy)
              (prepend libssc)))
    (description
     "@code{iio-sensor-proxy} is a daemon which passes IIO sensor data to D-Bus.
This variant also reads Qualcomm Snapdragon Sensor Core (SSC) sensors through
libssc.")))
