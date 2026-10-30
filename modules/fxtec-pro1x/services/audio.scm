;;; fxtec-pro1x/services/audio.scm — PipeWire + Pro1X UCM2/WirePlumber/voicepcm
;;;
;;; Translates modules/audio.nix.
;;;
;;; The key challenges vs. NixOS:
;;;   1. UCM2 merge: we need alsa-ucm-conf + pro1x UCM profiles in the same
;;;      tree, a computed union directory.  ALSA_CONFIG_UCM2 points at it in
;;;      the sessions, through pro1x-audio-session (below); an
;;;      /etc/environment.d file did that on NixOS (systemd) but nothing
;;;      reads that directory here.
;;;   0. PipeWire, WirePlumber and pipewire-pulse have no systemd user units
;;;      here: pro1x-audio-session starts them inside each graphical session
;;;      (after dbus-run-session) and stops them when the session ends.
;;;      WirePlumber gets the patched libcamera (same 0.7.2 ABI as the one
;;;      PipeWire links) through LD_LIBRARY_PATH, as on NixOS, so that the
;;;      cameras reach apps through PipeWire.
;;;      State: not yet run on the phone.
;;;   2. WirePlumber config: installed to /etc/wireplumber/wireplumber.conf.d/
;;;   3. pro1x-audio-init: run as a Shepherd one-shot before PipeWire starts.
;;;   4. pro1x-voicepcm user service: started/stopped by UCM VoiceCall verb.
;;;      Exposed as a system Shepherd service running as the session user.

(define-module (fxtec-pro1x services audio)
  #:use-module (fxtec-pro1x packages audio)
  #:use-module (fxtec-pro1x packages misc)  ; libcamera-pro1x
  #:use-module (gnu packages audio)
  #:use-module (gnu packages gnome)         ; wireplumber
  #:use-module (gnu packages base)          ; coreutils
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system pam)             ; session-environment-service-type
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix store)
  #:export (pro1x-audio-session
            pro1x-audio-configuration
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
    (with-imported-modules '((guix build utils))
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
           #:log (%make-void-port "w"))))))

;;; /etc entries: WirePlumber conf fragment and environment for ALSA_CONFIG_UCM2
(define (pro1x-audio-etc config)
  (let ((audio-pkg (pro1x-audio-configuration-package config)))
    (list
     ;; WirePlumber config fragment
     `("wireplumber/wireplumber.conf.d/52-pro1x-s16.conf"
       ,(file-append audio-pkg
                     "/share/wireplumber/wireplumber.conf.d/52-pro1x-s16.conf"))
     ;; No PulseAudio autospawn: a client started before pipewire-pulse
     ;; listened ran `pulseaudio --start', which took the socket, so
     ;; pipewire-pulse died and PulseAudio drove the card without our UCM
     ;; (generic profiles, no sound; 2026-10-30).  Clients wait instead.
     `("pulse/client.conf"
       ,(plain-file "client.conf" "autospawn = no\n")))))

;;; pro1x-audio-session PROGRAM ARGS...: start the user's audio daemons,
;;; run PROGRAM (the compositor) and stop them when it exits.  Runs inside
;;; the session's D-Bus (after dbus-run-session).
(define pro1x-audio-session
  (program-file
   "pro1x-audio-session"
   #~(begin
       (define (spawn program . args)
         (let ((pid (primitive-fork)))
           (if (zero? pid)
               (catch #t
                 (lambda () (apply execl program program args))
                 (lambda _ (primitive-exit 127)))
               pid)))

       (setenv "ALSA_CONFIG_UCM2" #$(pro1x-ucm-dir pro1x-audio))
       (let* ((pipewire (spawn #$(file-append pipewire "/bin/pipewire")))
              (pulse    (spawn #$(file-append pipewire "/bin/pipewire-pulse")))
              (wireplumber
               (begin
                 (sleep 1)              ;let PipeWire create its socket
                 (spawn #$(file-append coreutils "/bin/env")
                        (string-append "LD_LIBRARY_PATH="
                                       #$(file-append libcamera-pro1x "/lib"))
                        #$(file-append wireplumber "/bin/wireplumber"))))
              (status (apply system* (cdr (command-line)))))
         (for-each (lambda (pid)
                     (false-if-exception (kill pid SIGTERM)))
                   (list wireplumber pulse pipewire))
         (primitive-exit (or (status:exit-val status) 1))))))

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
    (list audio-pkg alsa-utils pulseaudio pipewire wireplumber)))

(define pro1x-audio-service-type
  (service-type
   (name 'pro1x-audio)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-audio-shepherd-services)
     (service-extension etc-service-type
                        pro1x-audio-etc)
     ;; libpulse reads /etc/pulse/client.conf (autospawn = no) only when
     ;; told to, as Guix's pulseaudio-service-type does.
     (service-extension session-environment-service-type
                        (const '(("PULSE_CLIENTCONFIG"
                                  . "/etc/pulse/client.conf"))))
     (service-extension profile-service-type
                        pro1x-audio-packages)))
   (default-value (pro1x-audio-configuration))
   (description "PipeWire audio for the F(x)tec Pro1X: UCM2 profiles, WirePlumber
S16LE fix, audio-init mixer setup, and the voicepcm session helper.")))
