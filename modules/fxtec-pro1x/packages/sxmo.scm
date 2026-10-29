;;; fxtec-pro1x/packages/sxmo.scm — Sxmo mobile UI packages
;;;
;;; Packages:
;;;   clickclack   — haptic/audio feedback for virtual keyboards
;;;   sxmo-utils   — scripts, hooks, and small C utilities for the Sxmo environment
;;;
;;; Most Sxmo dependencies are already in upstream Guix:
;;;   lisgd, svkbd, bonsai, sxmo-st, wvkbd, bemenu, swayidle, swaybg, wob
;;;
;;; Runtime tools needed in the user's profile for sway/Wayland Sxmo:
;;;   sway, bemenu, foot, wvkbd, swayidle, swaybg, bonsai, lisgd,
;;;   dunst, wob, gawk, curl, jq, inotify-tools, mpv, ffmpeg

(define-module (fxtec-pro1x packages sxmo)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages hare-apps)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages man)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages sdl)
  #:use-module (gnu packages window-management)
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (clickclack
            sxmo-utils))

(define-public clickclack
  (package
    (name "clickclack")
    (version "0.2.3")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://git.sr.ht/~proycon/clickclack/archive/" version ".tar.gz"))
       (sha256
        (base32 "1vfcfc69hgywcc234mdpvd2wncw2hjpv8g8mv1vkdcx83ap163wl"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:make-flags #~(list (string-append "PREFIX=" #$output)
                           "CC=gcc")
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure))))
    (inputs (list sdl2))
    (home-page "https://git.sr.ht/~proycon/clickclack")
    (synopsis "Haptic and audio feedback for virtual keyboards")
    (description
     "Clickclack provides haptic and audio feedback when using virtual
keyboards such as svkbd and wvkbd.  It can play a sound file and/or
trigger a vibration effect on each keypress.")
    (license license:gpl3+)))

(define-public sxmo-utils
  (package
    (name "sxmo-utils")
    (version "1.18.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://git.sr.ht/~mil/sxmo-utils/archive/" version ".tar.gz"))
       (sha256
        (base32 "1m6q4jlm0dzmnd1jz2mrzpvazvf3fhqg2i261jwqc6rkyxq69pk5"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:make-flags
      #~(list (string-append "PREFIX=" #$output)
              (string-append "SYSCONFDIR=" #$output "/etc")
              (string-append "SERVICEDIR=" #$output "/share/superd/services")
              "CC=gcc")
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-before 'build 'patch-scripts
            (lambda _
              ;; setup_config_version.sh uses busybox; replace with standard
              ;; POSIX tools available in the build environment.
              (substitute* "setup_config_version.sh"
                (("busybox ") ""))))
          (add-before 'install 'skip-setcap
            (lambda _
              ;; setcap cannot run in the build sandbox.  sxmo_sleep will work
              ;; without CAP_WAKE_ALARM but alarm-aligned sleep is degraded.
              ;; Set the capability post-install if needed:
              ;;   setcap 'cap_wake_alarm=ep' $(which sxmo_sleep)
              (substitute* "Makefile"
                (("\tsetcap.*\n") "\t@true\n"))))
          (add-after 'install 'remove-doas-config
            (lambda* (#:key outputs #:allow-other-keys)
              ;; doas is not used on Guix (wheel group / sudo handles privilege).
              (let ((etc (string-append (assoc-ref outputs "out") "/etc")))
                (when (file-exists? (string-append etc "/doas.d"))
                  (delete-file-recursively (string-append etc "/doas.d")))))))))
    (native-inputs (list pkg-config scdoc))
    ;; Runtime: the scripts reference many tools; the sway/Wayland variant
    ;; needs at minimum: sway bemenu foot wvkbd swayidle swaybg bonsai lisgd
    ;; dunst wob gawk curl jq inotify-tools mpv ffmpeg
    (propagated-inputs
     (list bonsai
           bemenu
           lisgd
           wvkbd
           swayidle
           swaybg))
    (home-page "https://sxmo.org")
    (synopsis "Scripts and utilities for the Sxmo mobile UI environment")
    (description
     "Sxmo (Simple X Mobile) is a minimalist mobile UI built around
sway/dwm and POSIX shell scripts.  This package provides the core scripts,
default hooks, app configs, and small C utilities (@command{sxmo_vibrate},
@command{sxmo_sleep}, @command{sxmo_aligned_sleep},
@command{sxmo_status_led}) that glue the environment together.

The sway/Wayland session is started via @command{sxmo_swayinit.sh} and
registered as a Wayland session in @file{share/wayland-sessions/swmo.desktop}.

@strong{Note:} @command{sxmo_sleep} requires @code{CAP_WAKE_ALARM} for
alarm-aligned suspend; run @code{setcap cap_wake_alarm=ep $(which sxmo_sleep)}
after installation to enable it.")
    (license license:agpl3)))
