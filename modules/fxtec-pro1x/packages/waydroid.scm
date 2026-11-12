;;; Waydroid: Android in an LXC container, on the Pro1X's own kernel.
;;;
;;; After phodina's Guix series (bug #51737, v3 of 2022-10-29, never merged;
;;; first as a gist, waydroid/waydroid#258), brought to current versions:
;;; libglibutil, libgbinder and gbinder-python, and Waydroid itself.  The
;;; kernel needs nothing more: binder, binderfs and PSI are in
;;; device/kernel/config.aarch64 already (from the NixOS port).
;;;
;;; The Android image is not packaged: `sudo waydroid init' downloads
;;; LineageOS, plain (VANILLA) or with Google's apps (`-s GAPPS').  The
;;; container starts through D-Bus activation (id.waydro.Container), as
;;; upstream does without systemd; services/waydroid.scm installs its bus
;;; and polkit policies.

(define-module (fxtec-pro1x packages waydroid)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages bison)
  #:use-module (gnu packages dns)
  #:use-module (gnu packages flex)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages virtualization)
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system pyproject)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:))

;; Both Sailfish libraries install under DESTDIR/usr; with DESTDIR the
;; output, usr/ is dropped from the paths.
(define (sailfish-library-phases pc-file)
  #~(modify-phases %standard-phases
      (delete 'configure)
      (add-after 'unpack 'drop-usr
        (lambda _
          (substitute* "Makefile"
            (("usr/") ""))
          (substitute* #$pc-file
            (("/usr/include") (string-append #$output "/include")))))
      (add-after 'install 'install-dev
        (lambda* (#:key make-flags #:allow-other-keys)
          (apply invoke "make" "install-dev" make-flags)))
      (replace 'check
        (lambda* (#:key tests? make-flags #:allow-other-keys)
          (when tests?
            (apply invoke "make" "-C" "unit" "test" make-flags))))))

(define-public libglibutil
  (package
    (name "libglibutil")
    (version "1.0.83")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/sailfishos/libglibutil")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0i8gdr4y6avpx0a3i0n4fcfnbrk00vwxbzx1z8z131yqw3ibim55"))))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f                  ;the unit tests need a writable /dev/shm
           #:make-flags
           #~(list (string-append "CC=" #$(cc-for-target))
                   (string-append "DESTDIR=" #$output)
                   "LIBDIR=lib")
           #:phases (sailfish-library-phases "libglibutil.pc.in")))
    (native-inputs (list pkg-config))
    (propagated-inputs (list glib))     ;libglibutil.pc requires glib-2.0
    (home-page "https://github.com/sailfishos/libglibutil")
    (synopsis "Library of GLib utilities")
    (description "libglibutil collects GLib utilities that libgbinder and
other Sailfish OS libraries use: logging, ring buffers, weak references and
more.")
    (license license:bsd-3)))

(define-public libgbinder
  (package
    (name "libgbinder")
    (version "1.1.55")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/mer-hybris/libgbinder")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "00rbwmkh9jq7hp1a8g9nml43dymjfd4lsf9znvdi64ylamfxwhnn"))))
    (build-system gnu-build-system)
    (arguments
     (list #:tests? #f                  ;the unit tests need /dev/binder
           #:make-flags
           #~(list (string-append "CC=" #$(cc-for-target))
                   (string-append "DESTDIR=" #$output)
                   "LIBDIR=lib")
           #:phases (sailfish-library-phases "libgbinder.pc.in")))
    (native-inputs (list bison flex pkg-config))
    (propagated-inputs (list glib libglibutil)) ;Requires.private
    (home-page "https://github.com/mer-hybris/libgbinder")
    (synopsis "GLib-style interface to Android's binder")
    (description "libgbinder talks to Android's binder IPC from GLib
programs: the event loop integration, 32- or 64-bit binder detected at run
time, asynchronous transactions, and a stable service manager API.")
    (license license:bsd-3)))

(define-public python-gbinder
  (package
    (name "python-gbinder")
    (version "1.1.1")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/waydroid/gbinder-python")
                    (commit (string-append "upstream/" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0wdpf6b6b3cmd42j1qkfp19y9bdymy5dv12r261gkhvxxh160zym"))))
    (build-system pyproject-build-system)
    (arguments
     (list #:tests? #f                  ;the tests need /dev/binder
           #:phases
           #~(modify-phases %standard-phases
               ;; distutils is gone from Python 3.12; setup.py builds
               ;; gbinder.c, which Cython makes from gbinder.pyx first.
               (add-after 'unpack 'use-setuptools
                 (lambda _
                   (substitute* "setup.py"
                     (("from distutils.core import")
                      "from setuptools import"))
                   (invoke "cython" "-3" "gbinder.pyx"))))))
    ;; Cython 3 rejects its callbacks (no noexcept); 0.29 builds it.
    (native-inputs (list pkg-config python-cython-0 python-setuptools))
    (inputs (list libgbinder))
    (home-page "https://github.com/waydroid/gbinder-python")
    (synopsis "Python bindings for libgbinder")
    (description "This package provides Python bindings for libgbinder, the
binder library that Waydroid talks to Android with.")
    (license license:gpl3+)))

(define-public waydroid
  (package
    (name "waydroid")
    (version "1.6.3")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/waydroid/waydroid")
                    (commit version)))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "1kkk83ww4v1p6glnnf4s9s2rfh5vmblvszhn17j4pyqnl950v1nm"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f                       ;no tests
      #:make-flags
      #~(list (string-append "PREFIX=" #$output)
              (string-append "SYSCONFDIR=" #$output "/etc")
              "USE_SYSTEMD=0"
              "USE_NFTABLES=1")
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (add-after 'install 'fix-paths
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((lib (string-append #$output "/lib/waydroid")))
                ;; D-Bus activation runs the container manager.
                (substitute* (string-append
                              #$output
                              "/share/dbus-1/system-services/id.waydro.Container.service")
                  (("/usr/bin/waydroid") (string-append #$output "/bin/waydroid"))
                  (("^SystemdService=.*") ""))
                (substitute* (find-files (string-append #$output "/share/applications")
                                         "\\.desktop$")
                  (("/usr/bin/waydroid") (string-append #$output "/bin/waydroid")))
                ;; The network script runs dnsmasq, ip and nft.
                (wrap-program (string-append lib "/data/scripts/waydroid-net.sh")
                  `("PATH" ":" prefix
                    ,(map (lambda (p) (string-append p "/bin"))
                          (list #$coreutils #$dnsmasq #$iproute #$nftables
                                #$kmod #$util-linux)))
                  `("PATH" ":" prefix
                    ,(map (lambda (p) (string-append p "/sbin"))
                          (list #$dnsmasq #$iproute #$nftables #$kmod)))))))
          (add-after 'fix-paths 'wrap
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((script (string-append #$output "/lib/waydroid/waydroid.py")))
                ;; bin/waydroid is a symbolic link to waydroid.py, which
                ;; finds its modules next to its real path.
                (wrap-program script
                  `("GUIX_PYTHONPATH" ":" prefix
                    (,(getenv "GUIX_PYTHONPATH")))
                  `("PATH" ":" prefix
                    ,(map (lambda (p) (string-append p "/bin"))
                          (list #$lxc #$util-linux #$kmod #$coreutils
                                #$iproute)))
                  `("PATH" ":" prefix
                    ,(map (lambda (p) (string-append p "/sbin"))
                          (list #$lxc #$util-linux #$kmod #$iproute))))))))))
    (inputs
     (list bash-minimal
           coreutils
           dnsmasq
           iproute
           kmod
           lxc
           nftables
           python
           python-dbus
           python-gbinder
           python-pyclip
           python-pygobject
           util-linux))
    (supported-systems '("aarch64-linux" "x86_64-linux"))
    (home-page "https://waydro.id")
    (synopsis "Android in a container")
    (description
     "Waydroid runs a full Android system, based on LineageOS, in an LXC
container with Linux namespaces, and shows its apps as Wayland windows.  The
Android image is downloaded by @command{waydroid init}.")
    (license license:gpl3)))
