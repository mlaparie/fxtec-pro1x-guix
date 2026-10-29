;;; fxtec-pro1x/packages/audio.scm — pro1x-audio: voicepcm + UCM2 + WirePlumber conf

(define-module (fxtec-pro1x packages audio)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages audio)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pulseaudio)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (pro1x-audio))

(define-public pro1x-audio
  (package
    (name "pro1x-audio")
    (version "1")
    ;; Source lives in device/audio/ within this repo.
    (source (local-file (repository-file "device/audio") "pro1x-audio-src" #:recursive? #t))
    (build-system gnu-build-system)
    (inputs
     (list alsa-lib alsa-utils pipewire pulseaudio
           gawk coreutils util-linux bash modem-manager))
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)

          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (invoke #$(cc-for-target) "-O2" "-Wall"
                      "-o" "pro1x-voicepcm" "voicepcm.c"
                      "-lasound")))

          (replace 'install
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out #$output)
                     (bin (string-append out "/bin"))
                     (ucm (string-append out "/share/alsa/ucm2"))
                     (wp  (string-append out "/share/wireplumber/wireplumber.conf.d"))
                     (path (string-join
                            (list (string-append #$alsa-utils "/bin")
                                  (string-append #$pipewire "/bin")
                                  (string-append #$pulseaudio "/bin")
                                  (string-append #$gawk "/bin")
                                  (string-append #$coreutils "/bin")
                                  (string-append #$util-linux "/bin")
                                  (string-append #$modem-manager "/bin")
                                  bin)
                            ":")))
                (mkdir-p bin)
                (mkdir-p ucm)
                (mkdir-p wp)

                ;; Compiled binary
                (install-file "pro1x-voicepcm" bin)
                (chmod (string-append bin "/pro1x-voicepcm") #o755)

                ;; Shell scripts — wrap with a hard PATH so they work even
                ;; from bare systemd units that have an empty environment.
                (for-each
                 (lambda (script)
                   (install-file script bin)
                   (chmod (string-append bin "/" script) #o755)
                   (wrap-program (string-append bin "/" script)
                     `("PATH" ":" prefix (,path))))
                 '("pro1x-audio-init" "pro1x-voice-call"))

                ;; UCM2 profiles
                (copy-recursively "ucm2" ucm)

                ;; WirePlumber fragment
                (for-each (lambda (f)
                            (install-file f wp))
                          (find-files "wireplumber.conf.d" "\\.conf$"))

                ;; Substitute the /usr/bin/env indirection in VoiceCall.conf so
                ;; the UCM verb works on Guix (no /usr/bin/env pro1x-voice-call).
                (substitute* (string-append ucm "/Pro1X/VoiceCall.conf")
                  (("/usr/bin/env pro1x-voice-call")
                   (string-append bin "/pro1x-voice-call")))))))))
    (home-page "https://github.com/sm6115-mainline/fxtec-pro1x-nixos")
    (synopsis "Audio tools and UCM2/WirePlumber config for the F(x)tec Pro1X")
    (description
     "Provides: pro1x-voicepcm (keeps the VoiceMMode1 hostless PCM open during
calls), pro1x-voice-call (start/stop the call session), pro1x-audio-init (sets
ALSA mixer gains before PipeWire starts), the Pro1X UCM2 use-case profiles, and
a WirePlumber fragment that forces S16LE to avoid the −40 dB volume bug.")
    (license license:gpl2+)))
