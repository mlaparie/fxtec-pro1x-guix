;;; fxtec-pro1x/packages/wl-cast.scm — wl-cast, the author's browser stream
;;; (codeberg.org/mlaparie/wl-cast, AGPL-3.0-or-later), packaged here to be
;;; tried in quick actions beside pro1x-stream's browser streams, which it
;;; is to replace once validated (author, 2026-11-22).  The port's buttons
;;; and hook for it: device/sway/wl-cast-{buttons,hook}, in etc/xdg/wl-cast.
;;;
;;; wl-cast: a Wayland screen in a browser, with touch, keys and sound.
;;;
;;; wl-cast-capture copies a wlroots output into GPU buffers, converts it to
;;; NV12 straight into a V4L2 hardware encoder's buffers and writes H.264;
;;; wl-cast-server serves the page and the stream by WebRTC and plays the
;;; viewer's input on virtual devices; wl-cast starts and stops it.
;;;
;;; Tested state: built for aarch64 from the author's private channel and
;;; used on the Pro¹x from the user profile (2026-11-22); not yet from here.

(define-module (fxtec-pro1x packages wl-cast)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages networking)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages video)
  #:use-module (gnu packages web)
  #:use-module ((gnu packages window-management) #:select (wl-mirror))
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define-public wl-cast
  (let ((commit "113f8949b6eadd34ed8d6df481f8bb57de5621bb")
        (revision "0"))
    (package
      (name "wl-cast")
      (version (git-version "0.1" revision commit))
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://codeberg.org/mlaparie/wl-cast")
               (commit commit)))
         (file-name (git-file-name name version))
         (sha256
          (base32 "191vyql1s8giy56pvw4d36mjv1zl5x8wyx79gbf8v6yw36wki174"))))
      (build-system gnu-build-system)
      (arguments
       (list
        #:tests? #f
        #:make-flags
        #~(list (string-append "CC=" #$(cc-for-target))
                (string-append "PREFIX=" #$output))
        #:phases
        #~(modify-phases %standard-phases
            (delete 'configure)
            (add-after 'install 'wrap
              (lambda* (#:key inputs #:allow-other-keys)
                (let* ((bin (string-append #$output "/bin"))
                       (in (lambda (dir names)
                             (map (lambda (p)
                                    (string-append (assoc-ref inputs p) dir))
                                  names)))
                       (path (cons* bin
                                    ;; ip and iw are in sbin.
                                    (string-append (assoc-ref inputs "iproute2")
                                                   "/sbin")
                                    (string-append (assoc-ref inputs "iw")
                                                   "/sbin")
                                    (in "/bin" '("jq" "wf-recorder" "curl"
                                                 "openssl" "wl-mirror"
                                                 "pipewire" "brightnessctl"
                                                 "procps" "pulseaudio")))))
                  (patch-shebang (string-append bin "/wl-cast-server")
                                 (list (string-append
                                        (assoc-ref inputs "python") "/bin")))
                  (wrap-program (string-append bin "/wl-cast-server")
                    `("GUIX_PYTHONPATH" prefix (,(getenv "GUIX_PYTHONPATH")))
                    `("GI_TYPELIB_PATH" ":" prefix
                      ,(in "/lib/girepository-1.0"
                           '("glib" "gobject-introspection" "gstreamer"
                             "gst-plugins-base" "gst-plugins-bad")))
                    `("GST_PLUGIN_SYSTEM_PATH" ":" prefix
                      ,(in "/lib/gstreamer-1.0"
                           '("gstreamer" "gst-plugins-base" "gst-plugins-good"
                             "gst-plugins-bad" "libnice" "pipewire")))
                    `("PATH" ":" prefix ,path))
                  ;; swaymsg comes from the session, the compositor's own.
                  (for-each (lambda (f)
                              (wrap-program (string-append bin "/" f)
                                `("PATH" ":" prefix ,path)))
                            '("wl-cast" "wl-cast-screen" "wl-cast-output"
                              "wl-cast-cert" "wl-cast-dns-cloudflare"
                              "wl-cast-dns-desec" "wl-cast-dns-porkbun")))))
            (add-after 'wrap 'install-examples
              (lambda _
                (copy-recursively
                 "examples"
                 (string-append #$output "/share/doc/wl-cast/examples")))))))
      (native-inputs (list pkg-config wayland-protocols wlr-protocols))
      (inputs
       (list bash-minimal brightnessctl curl glib gobject-introspection gst-plugins-bad
             gst-plugins-base gst-plugins-good gstreamer iproute iw jq libdrm
             libnice mesa openssl pipewire procps python python-evdev
             pulseaudio python-pygobject wayland wf-recorder wl-mirror))
      (home-page "https://codeberg.org/mlaparie/wl-cast")
      (synopsis "Use a Wayland screen from a browser, with touch and sound")
      (description "wl-cast streams a wlroots output to a web browser by
WebRTC, with its sound, and plays the viewer's touches and keys on the host
through virtual input devices.  The capture converts each frame on the GPU
straight into a V4L2 hardware H.264 encoder's buffers, with no CPU copy.")
      (license license:agpl3+))))
