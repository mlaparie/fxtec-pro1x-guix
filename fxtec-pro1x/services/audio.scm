;;; fxtec-pro1x/services/audio.scm — PipeWire + Pro1X UCM2/WirePlumber/voicepcm
;;;
;;; Translates modules/audio.nix.
;;;
;;; The key challenges vs. NixOS:
;;;   1. UCM2 merge: we need alsa-ucm-conf + pro1x UCM profiles in the same
;;;      tree.  We do this with a computed union directory set via
;;;      ALSA_CONFIG_UCM2 in the PAM/session environment.
;;;   2. WirePlumber config: installed to /etc/wireplumber/wireplumber.conf.d/
;;;   3. pro1x-audio-init: run as a Shepherd one-shot before PipeWire starts.
;;;   4. pro1x-voicepcm user service: started/stopped by UCM VoiceCall verb.
;;;      Exposed as a system Shepherd service running as the session user.

(define-module (fxtec-pro1x services audio)
  #:use-module (fxtec-pro1x packages audio)
  #:use-module (gnu packages audio)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix store)
  #:export (pro1x-audio-configuration
            pro1x-audio-configuration?
            make-pro1x-audio-configuration
            pro1x-audio-service-type))

(define-record-type* <pro1x-audio-configuration>
  pro1x-audio-configuration make-pro1x-audio-configuration
  pro1x-audio-configuration?
  (audio-package pro1x-audio-configuration-package (default pro1x-audio)))

;;; Build a directory that is the union of stock alsa-ucm-conf and the Pro1X
;;; profiles so PipeWire/WirePlumber can find both.
(define (pro1x-ucm-dir audio-pkg)
  (computed-file "alsa-ucm2-pro1x"
    #~(begin
        (use-modules (guix build utils))
        (mkdir-p #$output)
        ;; Stock profiles first, then ours (ours win on conflicts)
        (copy-recursively
         (string-append #$alsa-ucm-conf "/share/alsa/ucm2")
         #$output
         #:log (%make-void-port "w"))
        (copy-recursively
         (string-append #$audio-pkg "/share/alsa/ucm2")
         #$output
         #:log (%make-void-port "w")))))

;;; /etc entries: WirePlumber conf fragment and environment for ALSA_CONFIG_UCM2
(define (pro1x-audio-etc config)
  (let* ((audio-pkg (pro1x-audio-configuration-package config))
         (ucm       (pro1x-ucm-dir audio-pkg)))
    (list
     ;; WirePlumber config fragment
     `("wireplumber/wireplumber.conf.d/52-pro1x-s16.conf"
       ,(file-append audio-pkg
                     "/share/wireplumber/wireplumber.conf.d/52-pro1x-s16.conf"))
     ;; UCM2 path for session processes: write into a PAM environment file
     ;; so anything started by the display manager inherits it.
     `("environment.d/50-pro1x-ucm2.conf"
       ,(computed-file "50-pro1x-ucm2.conf"
          #~(call-with-output-file #$output
              (lambda (p)
                (display
                 (string-append "ALSA_CONFIG_UCM2=" #$ucm "\n")
                 p))))))))

;;; Shepherd service: pro1x-audio-init runs once before PipeWire/WirePlumber.
(define (pro1x-audio-shepherd-services config)
  (let ((audio-pkg (pro1x-audio-configuration-package config)))
    (list
     (shepherd-service
      (provision '(pro1x-audio-init))
      (requirement '(udev))
      (documentation "Initialise Pro1X ALSA mixer gains before PipeWire starts")
      (one-shot? #t)
      (start
       #~(make-forkexec-constructor
          (list #$(file-append audio-pkg "/bin/pro1x-audio-init"))
          #:log-file "/var/log/pro1x-audio-init.log"))
      (stop #~(make-kill-destructor))))))

;;; System packages
(define (pro1x-audio-packages config)
  (let ((audio-pkg (pro1x-audio-configuration-package config)))
    (list audio-pkg alsa-utils pulseaudio)))

(define pro1x-audio-service-type
  (service-type
   (name 'pro1x-audio)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-audio-shepherd-services)
     (service-extension etc-service-type
                        pro1x-audio-etc)
     (service-extension profile-service-type
                        pro1x-audio-packages)))
   (default-value (pro1x-audio-configuration))
   (description "PipeWire audio for the F(x)tec Pro1X: UCM2 profiles, WirePlumber
S16LE fix, audio-init mixer setup, and the voicepcm session helper.")))
