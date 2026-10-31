;;; fxtec-pro1x/services/hardware.scm — core hardware service type
;;;
;;; Translates modules/hardware.nix.  In Guix the kernel, bootloader and
;;; firmware live in the operating-system record rather than a service, so
;;; pro1x-hardware-service-type handles what CAN be a service:
;;;
;;;   • udev rules (cameras, haptics, slider)
;;;   • kernel parameters
;;;   • feedbackd group
;;;   • optional USB serial getty
;;;   • touch calibration matrix for display gaps
;;;   • double tap to wake the panel (pro1x-doubletap), double-tap-wake?;
;;;   • torch safety: a flash LED left on is switched off after torch-timeout
;;;     seconds (default 60), whoever turned it on;
;;;   • charge limit: stop charging at charge-limit percent, resume at or
;;;     below charge-resume (hysteresis, as Android's charge-limit tools
;;;     do), through pro1x_charger_icl's charge_enable (kernel patch
;;;     pro1x-charge-control).  USB keeps powering the phone meanwhile.
;;;     The percentage is estimated from voltage, which drops when charging
;;;     stops: keep the gap wider than that drop (not measured yet);
;;;   • light or dark apps (color-scheme, default 'prefer-dark): GSettings;
;;;   • lock screen keyboard (lock-keyboard, 'dark or 'light): /etc/pro1x/lock.conf;
;;;   • on-screen keyboard haptics (keyboard-haptics?, default #t): feedbackd theme;
;;;   • blank and lock after idle (blank-after, lock-after): GSettings defaults
;;;     for Phosh (idle-delay, lock-delay; a value set in GNOME Settings
;;;     wins) and /etc/pro1x/dim.conf for Sway (pro1x-idle --sway, swaylock);
;;;   • notification LED colours (notification-leds): a feedbackd device
;;;     theme, share/feedbackd/themes/fxtec,pro1x.json in the system profile,
;;;     which feedbackd loads for its default theme on this phone.
;;;     Default: messages blue, missed calls purple, terminal bell white.
;;;     In config.scm, (notification-leds '(("message-missed-sms" "green")
;;;     ("phone-missed-call" "#FF8000" 1000))) replaces that list.  Events: battery-caution,
;;;     message-missed-email, -instant, -notification, -sms,
;;;     notification-missed-generic, phone-missed-call;
;;;   • battery on the notification LED (charging-led, charged-led,
;;;     low-battery-led, low-battery-level): dim yellow breathing while
;;;     charging, steady green once full or held at the charge limit, a
;;;     short red blip every 4 s on low battery; feedbackd's notification
;;;     patterns take precedence;
;;;   • idle dimming of the panel: /etc/pro1x/dim.conf, read by pro1x-idle
;;;     and pro1x-dim (pro1x-sway-config) in the Sway and Phosh sessions.
;;;     In config.scm:
;;;       (modify-services (operating-system-user-services base)
;;;         (pro1x-hardware-service-type
;;;          config => (pro1x-hardware-configuration
;;;                     (inherit config) (dim-after 120) (dim-level 10))))
;;;
;;; The operating-system record in systems/ provides the kernel, firmware and
;;; bootloader directly — see systems/minimal.scm.

(define-module (fxtec-pro1x services hardware)
  #:use-module (fxtec-pro1x files)
  #:use-module (fxtec-pro1x packages misc)  ; pro1x-doubletap
  #:use-module (fxtec-pro1x packages sensors) ; monitor-sensor
  #:use-module (gnu packages linux)         ; kmod
  #:use-module (gnu services)
  #:use-module (gnu packages base)          ; coreutils
  #:use-module (gnu packages bash)          ; bash-minimal
  #:use-module ((gnu packages window-management) #:select (swayfx))
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system accounts)
  #:use-module (gnu system shadow)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix diagnostics)            ; formatted-message
  #:use-module (guix i18n)                   ; G_
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)                ; string-every
  #:use-module (srfi srfi-34)                ; raise
  #:export (pro1x-hardware-configuration
            pro1x-hardware-configuration?
            make-pro1x-hardware-configuration
            pro1x-hardware-service-type))

(define-record-type* <pro1x-hardware-configuration>
  pro1x-hardware-configuration make-pro1x-hardware-configuration
  pro1x-hardware-configuration?
  ;; Display gap (rows to black out at top/bottom for rounded corners / dead rows)
  (display-top-gap    pro1x-hardware-display-top-gap    (default 0))
  (display-bottom-gap pro1x-hardware-display-bottom-gap (default 0))
  ;; Enable USB serial gadget console (ttyGS0) as rescue line
  (serial-enable?     pro1x-hardware-serial-enable?     (default #f))
  ;; Extra kernel verbosity (earlycon, ignore_loglevel)
  (verbose?           pro1x-hardware-verbose?           (default #f))
  ;; fbcon rotation: 0 portrait, 1 clockwise, 2 upside-down, 3 CCW
  (console-rotation   pro1x-hardware-console-rotation   (default #f))
  ;; Dim the panel after this many seconds without input (#f: never), to
  ;; this percentage of its maximum brightness.
  (dim-after          pro1x-hardware-dim-after          (default 150))
  (dim-level          pro1x-hardware-dim-level          (default 20))
  ;; Blank the panel after this many seconds without input, and lock this
  ;; many seconds after blanking (0: when it blanks; #f: never lock).
  ;; 60 s was too short in Phosh and Sway (author, 2026-10-30); dimming
  ;; comes 30 s before the blank.
  (blank-after        pro1x-hardware-blank-after        (default 180))
  (lock-after         pro1x-hardware-lock-after         (default 120))
  ;; Light or dark apps and shell: 'prefer-dark (default, author) or
  ;; 'default (light).  A GSettings default (org.gnome.desktop.interface
  ;; color-scheme, plus Adwaita-dark for GTK 3 apps); a choice made in GNOME
  ;; Settings or with gsettings wins.  Sway passes it to libadwaita apps
  ;; (Calls, Chatty) through the GTK portal.
  (color-scheme       pro1x-hardware-color-scheme       (default 'prefer-dark))
  ;; A short vibration on each on-screen keyboard key (stevia), in
  ;; feedbackd's quiet and full profiles (author).
  (keyboard-haptics?  pro1x-hardware-keyboard-haptics?  (default #t))
  ;; The lock screen's on-screen keyboard (Sway, gtklock): 'dark or 'light.
  (lock-keyboard      pro1x-hardware-lock-keyboard      (default 'dark))
  ;; Wake the panel with a double tap while it is off.
  (double-tap-wake?   pro1x-hardware-double-tap-wake?   (default #t))
  ;; Stop charging at this battery percentage (#f: charge to full), and
  ;; charge again at or below charge-resume.
  (charge-limit       pro1x-hardware-charge-limit       (default 85))
  (charge-resume      pro1x-hardware-charge-resume      (default 80))
  ;; Switch a flash LED (torch) off after this many seconds on; #f: never.
  (torch-timeout      pro1x-hardware-torch-timeout      (default 60))
  ;; Notification LED colours, for feedbackd: a list of (EVENT COLOUR) or
  ;; (EVENT COLOUR PERIOD-MS); COLOUR is "red", "green", "blue", "white" or
  ;; "#RRGGBB".  Events not listed keep feedbackd's defaults.  Default
  ;; (author): blue for messages, purple for missed calls, white for the
  ;; terminal bell (foot's [bell], feedbackd's bell-terminal event).
  (notification-leds  pro1x-hardware-notification-leds
                      (default '(("message-missed-sms" "blue")
                                 ("message-missed-instant" "blue")
                                 ("phone-missed-call" "#8000FF")
                                 ("bell-terminal" "white"))))
  ;; The notification LED while charging (breathing), once full or held
  ;; at the charge limit (steady), and on battery at or below
  ;; low-battery-level percent (a short blip every 4 s): "#RRGGBB" or a
  ;; colour name as in notification-leds, #f for off.  Dim, and
  ;; notifications take the LED over.
  (charging-led       pro1x-hardware-charging-led       (default "#FFA000"))
  (charged-led        pro1x-hardware-charged-led        (default "#00FF00"))
  (low-battery-led    pro1x-hardware-low-battery-led    (default "#FF4000"))
  (low-battery-level  pro1x-hardware-low-battery-level  (default 15)))

;;; Colour names and "#RRGGBB" as "R G B" for multi_intensity, or #f.
(define (led-intensity colour)
  (match colour
    (#f #f)
    ("red" "255 0 0") ("green" "0 255 0") ("blue" "0 0 255")
    ("white" "255 255 255")
    ((? led-colour?)
     (string-join (map (lambda (i)
                         (number->string
                          (string->number (substring colour i (+ i 2)) 16)))
                       '(1 3 5))
                  " "))
    (_ (raise (formatted-message
               (G_ "charging-led/charged-led: ~s is not red, green, blue, \
white, #RRGGBB or #f")
               colour)))))

(define (pro1x-charge-led-program charging charged low low-level)
  ;; Polls the battery every 10 s.  It writes the LED only while it is dark
  ;; or showing its own colour, so feedbackd's notification patterns win and
  ;; ours comes back once they end.  It keeps the pattern trigger feedbackd
  ;; needs: off is a zero pattern, not brightness 0.  ledtrig-pattern ramps
  ;; linearly between entries; a 0 ms entry jumps.
  (program-file
   "pro1x-charge-led"
   #~(begin
       (use-modules (ice-9 rdelim))
       (define led "/sys/class/leds/rgb:status/")
       (define breathe "0 1500 32 1500")              ;charging
       (define steady "32 1000 32 1000")              ;full, held
       (define blip "40 150 40 0 0 4000 0 0")         ;low battery
       (define (read-file file)
         (or (false-if-exception (call-with-input-file file read-line)) ""))
       (define (write-file file value)
         (false-if-exception
          (call-with-output-file file (lambda (port) (display value port)))))
       (define (wanted)                   ;(intensity . pattern) or #f
         (let ((status (read-file "/sys/class/power_supply/battery/status"))
               (pct (string->number
                     (read-file "/sys/class/power_supply/battery/capacity")))
               (held (equal? "N" (read-file "/sys/module/pro1x_charger_icl/parameters/charge_enable"))))
           (define (on colour pattern) (and colour (cons colour pattern)))
           (cond ((and (equal? status "Discharging") pct (<= pct #$low-level))
                  (on #$low blip))
                 ((equal? status "Discharging") #f)
                 (held (on #$charged steady))
                 ((equal? status "Charging") (on #$charging breathe))
                 ((member status '("Full" "Not charging")) (on #$charged steady))
                 (else #f))))
       (let loop ((mine #f))              ;what we set, or #f
         (let* ((want (wanted))
                (colour (read-file (string-append led "multi_intensity")))
                (dark? (equal? (read-file (string-append led "brightness")) "0"))
                ;; Still ours: our colour (a breathing LED can read 0).
                (ours? (and mine (equal? colour (car mine)))))
           (cond ((and want (equal? want mine) ours?)
                  (sleep 10) (loop mine))
                 ((and want (or ours? dark?))
                  (write-file (string-append led "multi_intensity") (car want))
                  (write-file (string-append led "pattern") (cdr want))
                  (sleep 10) (loop want))
                 ((and (not want) ours?)
                  (write-file (string-append led "pattern") "0 1000 0 1000")
                  (sleep 10) (loop #f))
                 (else
                  (sleep 10) (loop (and ours? mine)))))))))

(define (pro1x-charge-led-shepherd-service config)
  (let ((charging (led-intensity (pro1x-hardware-charging-led config)))
        (charged (led-intensity (pro1x-hardware-charged-led config)))
        (low (led-intensity (pro1x-hardware-low-battery-led config))))
    (if (or charging charged low)
        (list
         (shepherd-service
          (provision '(pro1x-charge-led))
          (requirement '(udev))
          (documentation "Show charging on the notification LED.")
          (start #~(make-forkexec-constructor
                    (list #$(pro1x-charge-led-program
                             charging charged low
                             (pro1x-hardware-low-battery-level config)))
                    #:log-file "/var/log/pro1x-charge-led.log"))
          (stop #~(make-kill-destructor))
          (respawn? #t)))
        '())))

;;; feedbackd's own LED events and blink periods (data/default.json, 0.8.1),
;;; used when an entry of notification-leds gives no period.
(define %feedbackd-led-periods
  '(("battery-caution" . 5000)
    ("message-missed-email" . 2000)
    ("message-missed-instant" . 1000)
    ("message-missed-notification" . 500)
    ("message-missed-sms" . 2000)
    ("notification-missed-generic" . 500)
    ("phone-missed-call" . 3000)))

(define (led-colour? colour)
  (or (member colour '("red" "green" "blue" "white"))
      (and (= (string-length colour) 7)
           (char=? (string-ref colour 0) #\#)
           (string-every (char-set-union (char-set #\a #\b #\c #\d #\e #\f
                                                   #\A #\B #\C #\D #\E #\F)
                                         char-set:digit)
                         colour 1))))

(define (pro1x-feedbackd-theme-json leds haptics?)
  ;; A feedbackd device theme (named after the device tree compatible) that
  ;; inherits feedbackd's default theme and replaces its LED entries.  With
  ;; HAPTICS?, also a short vibration for stevia's key-pressed event, which
  ;; feedbackd's default theme leaves without feedback, and a stronger one
  ;; for button-pressed (Shift, layout keys): the default's 7 ms at 0.2
  ;; ran but could not be felt on this motor (aw86224).  In the quiet
  ;; profile, so in quiet and full.
  (define (entry spec)
    (match spec
      ((event colour . rest)
       (unless (led-colour? colour)
         (raise (formatted-message
                 (G_ "notification-leds: ~s: colour ~s is not red, green, \
blue, white or #RRGGBB")
                 event colour)))
       (let ((period (match rest
                       ((p) p)
                       (() (or (assoc-ref %feedbackd-led-periods event) 1000)))))
         (format #f "        { \"event-name\": ~s, \"type\": \"Led\",
          \"color\": ~s, \"frequency\": ~a }"
                 event colour period)))))
  (string-append
   "{\n  \"name\": \"fxtec,pro1x\",\n  \"parent-name\": \"default\",\n"
   "  \"profiles\": [\n    { \"name\": \"silent\",\n      \"feedbacks\": [\n"
   (string-join (map entry leds) ",\n")
   "\n      ]\n    }"
   (if haptics?
       ",\n    { \"name\": \"quiet\",\n      \"feedbacks\": [
        { \"event-name\": \"key-pressed\", \"type\": \"VibraPattern\",
          \"magnitudes\": [0.6], \"durations\": [20] },
        { \"event-name\": \"button-pressed\", \"type\": \"VibraPattern\",
          \"magnitudes\": [0.6], \"durations\": [20] }\n      ]\n    }"
       "")
   "\n  ]\n}\n"))

(define (pro1x-feedbackd-theme config)
  ;; No LED colours and no key haptics: no theme, feedbackd's defaults.
  (match (list (pro1x-hardware-notification-leds config)
               (pro1x-hardware-keyboard-haptics? config))
    ((() #f) '())
    ((leds haptics?)
     (let ((json (plain-file "pro1x-feedbackd-theme.json"   ;no "," in store names
                             (pro1x-feedbackd-theme-json leds haptics?))))
       (list
        (package
          (name "pro1x-feedbackd-theme")
          (version "0.1")
          (source #f)
          (build-system trivial-build-system)
          (arguments
           (list
            #:modules '((guix build utils))
            #:builder
            #~(begin
                (use-modules (guix build utils))
                (let ((dir (string-append #$output "/share/feedbackd/themes")))
                  (mkdir-p dir)
                  (copy-file #$json (string-append dir "/fxtec,pro1x.json"))))))
          (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
          (synopsis "Pro1X notification LED colours for feedbackd")
          (description "feedbackd device theme with the notification LED
colours from the system configuration.")
          (license license:gpl3+)))))))

(define (pro1x-udev-rules config)
  ;; Returns a file-like object: the base rules optionally extended with a
  ;; touch calibration matrix rule when display gaps are configured.
  (let* ((top    (pro1x-hardware-display-top-gap    config))
         (bottom (pro1x-hardware-display-bottom-gap config))
         (gap?   (> (+ top bottom) 0))
         (base   (local-file (repository-file "device/udev/60-pro1x.rules")
                             "60-pro1x.rules")))
    (if gap?
        (let* ((even   (lambda (g) (- g (modulo g 2))))
               (gtop   (even top))
               (gbot   (even bottom))
               (active (- 2160 gtop gbot))
               (scale  (exact->inexact (/ 2160 active)))
               (offset (exact->inexact (/ (- gtop) active)))
               (touch-rule
                (string-append
                 "ACTION!=\"remove\", SUBSYSTEM==\"input\","
                 " ENV{ID_INPUT_TOUCHSCREEN}==\"1\","
                 " ENV{LIBINPUT_CALIBRATION_MATRIX}=\""
                 "1 0 0 0 " (number->string scale) " " (number->string offset) "\"\n")))
          (mixed-text-file "60-pro1x.rules" base touch-rule))
        base)))

;;; The clock from the RTC.  The PMIC's RTC keeps running but Linux cannot
;;; set it (TrustZone; moWerk's SailfishOS notes), so the clock came up in
;;; 1970 until NTP stepped it, and not at all without network.  Keep the
;;; offset between real time and the RTC: saved when the service stops (at
;;; shutdown), applied at boot.  Only a time after 2025 counts as real, so a
;;; boot without network never saves a 1970 offset.  The first boot after a
;;; flash has no offset yet.
;;;
;;; State: not yet run on the phone.
(define pro1x-clock-script
  (mixed-text-file
   "pro1x-clock"
   "#!" (file-append bash-minimal "/bin/sh") "
PATH=" coreutils "/bin
rtc=/sys/class/rtc/rtc0/since_epoch
state=/var/lib/pro1x-clock/offset
real=1735689600   # 2025-01-01: anything earlier is not a real time
[ -r \"$rtc\" ] || { echo \"pro1x-clock: no $rtc\"; exit 0; }
case \"$1\" in
  restore)
    [ -r \"$state\" ] || { echo 'pro1x-clock: no saved offset yet'; exit 0; }
    now=$(date +%s)
    [ \"$now\" -ge \"$real\" ] && { echo 'pro1x-clock: clock already set'; exit 0; }
    t=$(( $(cat \"$rtc\") + $(cat \"$state\") ))
    date -u -s \"@$t\" >/dev/null && echo \"pro1x-clock: clock set from the RTC: $(date -u)\" ;;
  save)
    now=$(date +%s)
    [ \"$now\" -ge \"$real\" ] || { echo 'pro1x-clock: clock not set, offset not saved'; exit 0; }
    mkdir -p \"${state%/*}\"
    echo $(( now - $(cat \"$rtc\") )) > \"$state.new\" && mv \"$state.new\" \"$state\"
    echo \"pro1x-clock: offset saved ($(cat \"$state\") s)\" ;;
esac
"))

(define (pro1x-doubletap-shepherd-service config)
  (if (pro1x-hardware-double-tap-wake? config)
      (list
       (shepherd-service
        (provision '(pro1x-doubletap))
        (requirement '(udev))
        (documentation "Wake the panel with a double tap on the touchscreen.")
        (start
         #~(lambda args
             ;; uinput is a module; the power-key device needs /dev/uinput.
             (system* #$(file-append kmod "/bin/modprobe") "uinput")
             ((make-forkexec-constructor
               (list #$(file-append pro1x-doubletap "/bin/pro1x-doubletap"))
               #:log-file "/var/log/pro1x-doubletap.log")
              args)))
        (stop #~(make-kill-destructor))
        (respawn? #t)))
      '()))

(define pro1x-pocket-program
  ;; /run/pro1x-pocket exists while the proximity sensor sees something
  ;; near (monitor-sensor, through iio-sensor-proxy): pro1x-doubletap does
  ;; not wake the panel then, so a phone in a pocket stays dark.  In Sway,
  ;; near for two seconds without touches, the panel goes off and touch is disabled
  ;; (author, 2026-10-31: a covered phone kept its screen on); away again,
  ;; touch comes back, and the panel too if it was on before.  During calls
  ;; pro1x-call-watch also lights the panel when the phone leaves the ear.
  (program-file
   "pro1x-pocket"
   #~(begin
       (use-modules (ice-9 popen) (ice-9 rdelim) (ice-9 ftw) (ice-9 match)
                    (ice-9 textual-ports) (srfi srfi-1))
       (define flag "/run/pro1x-pocket")
       (define swaymsg #$(file-append swayfx "/bin/swaymsg"))
       ;; Reap the delayed-blanking children.  (Not SIGCHLD ignored: then
       ;; system* fails with "No child processes", which crashed the
       ;; service at start, 2026-10-31.)
       (define (reap!)
         (let loop ()
           (match (false-if-exception (waitpid WAIT_ANY WNOHANG))
             ((pid . _) (unless (zero? pid) (loop)))
             (_ #t))))
       (define (live-socket? f)         ;sway-ipc.UID.PID.sock, PID alive
         (match (string-split f #\.)
           ((_ _ pid _) (file-exists? (string-append "/proc/" pid)))
           (_ #f)))
       (define (sway-sockets)           ;every running Sway's IPC socket
         (append-map
          (lambda (uid)
            (map (lambda (f) (string-append "/run/user/" uid "/" f))
                 (or (scandir (string-append "/run/user/" uid)
                              (lambda (f) (and (string-prefix? "sway-ipc." f)
                                               (live-socket? f))))
                     '())))
          (or (scandir "/run/user" (lambda (f) (string->number f))) '())))
       (define (sway! command)
         (for-each (lambda (sock)
                     (system* swaymsg "-s" sock command))
                   (sway-sockets)))
       (define blanked "/run/pro1x-pocket-blanked") ;we turned it off
       (define (touch-interrupts)       ;the Goodix controller's IRQ count
         (call-with-input-file "/proc/interrupts"
           (lambda (port)
             (let loop ()
               (let ((line (read-line port)))
                 (cond ((eof-object? line) 0)
                       ((string-contains line "gt9286")
                        (apply + (filter-map string->number
                                             (cdr (string-tokenize line)))))
                       (else (loop))))))))
       (define (panel-on?)              ;any Sway output powered on
         (any (lambda (sock)
                (let* ((port (open-pipe* OPEN_READ swaymsg "-s" sock
                                         "-t" "get_outputs" "-r"))
                       (text (get-string-all port)))
                  (close-pipe port)
                  (string-contains text "\"power\": true")))
              (sway-sockets)))
       (define (set-near! near?)
         (if near?
             (begin
               (close-port (open-output-file flag))
               ;; Two seconds later, still near and no touch meanwhile: off,
               ;; and no touch input.  A finger scrolling near the sensor
               ;; reads near too, but it touches the screen (the touch
               ;; controller's interrupts); a pocket does not.  Note whether
               ;; the panel was on, to light it again when away.
               (when (zero? (primitive-fork))
                 (let ((touches (touch-interrupts)))
                   (sleep 2)
                   (unless (and (file-exists? flag)
                                (< (- (touch-interrupts) touches) 3))
                     (primitive-_exit 0)))
                 (when (file-exists? flag)
                   (when (panel-on?)
                     (close-port (open-output-file blanked)))
                   (sway! "input type:touch events disabled")
                   (sway! "output * power off"))
                 (primitive-_exit 0)))
             (begin
               (false-if-exception (delete-file flag))
               (sway! "input type:touch events enabled")
               ;; Back as it was: on if it was on (a lock screen stays
               ;; locked, it is only lit again).
               (when (file-exists? blanked)
                 (false-if-exception (delete-file blanked))
                 (sway! "output * power on")))))
       (set-near! #f)
       (let ((port (open-pipe* OPEN_READ
                               #$(file-append iio-sensor-proxy-ssc
                                              "/bin/monitor-sensor")
                               "--proximity")))
         ;; "=== Has proximity sensor (near: 1)" first, then
         ;; "    Proximity value changed: 0".
         (let loop ()
           (let ((line (read-line port)))
             (unless (eof-object? line)
               (reap!)
               (cond ((or (string-contains line "near: 1")
                          (string-contains line "value changed: 1"))
                      (set-near! #t))
                     ((or (string-contains line "near: 0")
                          (string-contains line "value changed: 0"))
                      (set-near! #f)))
               (loop))))
         (set-near! #f)
         (close-pipe port)))))

(define (pro1x-pocket-shepherd-service config)
  (if (pro1x-hardware-double-tap-wake? config)
      (list
       (shepherd-service
        (provision '(pro1x-pocket))
        (requirement '(iio-sensor-proxy))
        (documentation "Note when the proximity sensor sees something near.")
        (start #~(make-forkexec-constructor
                  (list #$pro1x-pocket-program)
                  #:log-file "/var/log/pro1x-pocket.log"))
        (stop #~(make-kill-destructor))
        (respawn? #t)))
      '()))

(define (pro1x-torch-guard-program timeout)
  (program-file
   "pro1x-torch-guard"
   #~(begin
       (use-modules (ice-9 ftw) (ice-9 rdelim) (srfi srfi-1))
       ;; The phone's flash LEDs: white:flash-0, amber:flash-1.
       (define (flash-leds)
         (map (lambda (f) (string-append "/sys/class/leds/" f))
              (or (scandir "/sys/class/leds"
                           (lambda (f) (string-contains f ":flash")))
                  '())))
       (define (on? led)
         (let ((v (false-if-exception
                   (call-with-input-file (string-append led "/brightness")
                     read-line))))
           (and v (not (equal? v "0")))))
       (define (off! led)
         (call-with-output-file (string-append led "/brightness")
           (lambda (port) (display "0" port)))
         (format #t "~a on for ~as: switched off~%" led #$timeout)
         (force-output))
       ;; SINCE: alist of LED -> time it was first seen on.
       (let loop ((since '()))
         (sleep 2)
         (let* ((now (current-time))
                (since (filter-map
                        (lambda (led)
                          (and (on? led)
                               (cons led (or (assoc-ref since led) now))))
                        (flash-leds))))
           (for-each (lambda (entry)
                       (when (>= (- now (cdr entry)) #$timeout)
                         (off! (car entry))))
                     since)
           (loop (remove (lambda (entry)
                           (>= (- now (cdr entry)) #$timeout))
                         since)))))))

(define (pro1x-torch-guard-shepherd-service config)
  (let ((timeout (pro1x-hardware-torch-timeout config)))
    (if timeout
        (list
         (shepherd-service
          (provision '(pro1x-torch-guard))
          (requirement '(file-systems))
          (documentation "Switch the torch off after it has been on a while.")
          (start #~(make-forkexec-constructor
                    (list #$(pro1x-torch-guard-program timeout))
                    #:log-file "/var/log/pro1x-torch-guard.log"))
          (stop #~(make-kill-destructor))
          (respawn? #t)))
        '())))

(define (pro1x-charge-limit-program limit resume)
  (program-file
   "pro1x-charge-limit"
   #~(begin
       (use-modules (ice-9 rdelim))
       (define param
         "/sys/module/pro1x_charger_icl/parameters/charge_enable")
       (define capacity "/sys/class/power_supply/battery/capacity")
       (define (read-file file)
         (false-if-exception (call-with-input-file file read-line)))
       (define (set-charging! on?)
         (call-with-output-file param
           (lambda (port) (display (if on? "1" "0") port)))
         (format #t "~a%: charging ~a~%" (read-file capacity)
                 (if on? "allowed" "held off"))
         (force-output))
       (if (not (file-exists? param))
           (begin
             (format #t "~a missing: this kernel has no charge control~%"
                     param)
             (force-output)
             ;; Stay up (no respawn loop) and do nothing.
             (let idle () (sleep 3600) (idle)))
           (let loop ()
             (let ((pct (string->number (or (read-file capacity) "")))
                   (on? (equal? "Y" (read-file param))))
               (cond ((not pct) #t)
                     ((and on? (>= pct #$limit)) (set-charging! #f))
                     ((and (not on?) (<= pct #$resume)) (set-charging! #t))))
             (sleep 60)
             (loop))))))

(define (pro1x-charge-limit-shepherd-service config)
  (let ((limit (pro1x-hardware-charge-limit config)))
    (if limit
        (list
         (shepherd-service
          (provision '(pro1x-charge-limit))
          (requirement '(file-systems))
          (documentation "Stop charging at the charge limit, resume below it.")
          (start #~(make-forkexec-constructor
                    (list #$(pro1x-charge-limit-program
                             limit (pro1x-hardware-charge-resume config)))
                    #:log-file "/var/log/pro1x-charge-limit.log"))
          ;; Stopping the service lets the battery charge to full again.
          (stop #~(lambda (running . args)
                    (apply (make-kill-destructor) running args)
                    (false-if-exception
                     (call-with-output-file
                         "/sys/module/pro1x_charger_icl/parameters/charge_enable"
                       (lambda (port) (display "1" port))))
                    #f))
          (respawn? #t)))
        '())))

(define (pro1x-clock-shepherd-service config)
  (list
   (shepherd-service
    (provision '(pro1x-clock))
    (requirement '(file-systems))
    (documentation "Set the clock from the RTC at boot, save its offset at shutdown")
    (start #~(lambda _
               (system* "/bin/sh" #$pro1x-clock-script "restore")
               #t))
    (stop #~(lambda _
              (system* "/bin/sh" #$pro1x-clock-script "save")
              #f)))))

(define (pro1x-hardware-account-groups config)
  (list (user-group (name "feedbackd") (system? #t))))

;; feedbackd's own rule for status LEDs (its data/90-feedbackd.rules),
;; which Guix's package does not install, with store paths: the RGB
;; notification LED (rgb:status) is tagged for feedbackd, gets the pattern
;; trigger (ledtrig-pattern, CONFIG_LEDS_TRIGGER_PATTERN) and its
;; attributes are given to group feedbackd by fbd-ledctrl.
(define pro1x-feedbackd-led-rules
  (mixed-text-file
   "90-pro1x-feedbackd-led.rules"
   "SUBSYSTEM==\"leds\", DEVPATH==\"*/*:status\", ENV{FEEDBACKD_TYPE}=\"led\", "
   "RUN{builtin}+=\"kmod load ledtrig-pattern\", RUN+=\""
   feedbackd-0.8 "/libexec/fbd-ledctrl -p %S%p -t pattern -G feedbackd\"\n"))

(define (pro1x-hardware-etc config)
  ;; /etc/pro1x/dim.conf, shell variables for pro1x-idle and pro1x-dim, and
  ;; /etc/pro1x/charge.conf.
  (let ((after (pro1x-hardware-dim-after config)))
    `(("pro1x/dim.conf"
       ,(plain-file "dim.conf"
                    (string-append
                     "# Written by pro1x-hardware-service-type (config.scm).\n"
                     "DIM_AFTER=" (if after (number->string after) "") "\n"
                     "DIM_LEVEL="
                     (number->string (pro1x-hardware-dim-level config))
                     "\n"
                     "BLANK_AFTER="
                     (number->string (pro1x-hardware-blank-after config))
                     "\n"
                     "LOCK_AFTER="
                     (let ((lock (pro1x-hardware-lock-after config)))
                       (if lock (number->string lock) ""))
                     "\n")))
      ;; /etc/pro1x/lock.conf: the lock screen keyboard's colours, for
      ;; pro1x-lock.
      ("pro1x/lock.conf"
       ,(plain-file "lock.conf"
                    (string-append
                     "# Written by pro1x-hardware-service-type (config.scm).\n"
                     "KEYBOARD="
                     (symbol->string (pro1x-hardware-lock-keyboard config))
                     "\n")))
      ;; /etc/pro1x/charge.conf: the charge limit, for sway-quick-actions
      ;; to show (the service itself gets the values directly).
      ("pro1x/charge.conf"
       ,(plain-file "charge.conf"
                    (let ((limit (pro1x-hardware-charge-limit config)))
                      (string-append
                       "# Written by pro1x-hardware-service-type (config.scm).\n"
                       "CHARGE_LIMIT=" (if limit (number->string limit) "") "\n"
                       "CHARGE_RESUME="
                       (if limit
                           (number->string (pro1x-hardware-charge-resume config))
                           "")
                       "\n")))))))

(define (pro1x-idle-gsettings config)
  ;; Phosh's blank and lock delays as system-wide GSettings defaults: an
  ;; override in the system profile, compiled by Guix's glib-schemas hook.
  (let ((blank (pro1x-hardware-blank-after config))
        (lock (pro1x-hardware-lock-after config))
        (scheme (symbol->string (pro1x-hardware-color-scheme config))))
    (package
      (name "pro1x-idle-gsettings")
      (version "0.1")
      (source #f)
      (build-system trivial-build-system)
      (arguments
       (list
        #:modules '((guix build utils))
        #:builder
        #~(begin
            (use-modules (guix build utils))
            (let ((dir (string-append #$output "/share/glib-2.0/schemas")))
              (mkdir-p dir)
              (call-with-output-file
                  (string-append dir "/92_pro1x-idle.gschema.override")
                (lambda (port)
                  ;; Twice: Phosh's own override sets idle-delay=60 for
                  ;; the Phosh desktop ([...:Phosh], when XDG_CURRENT_DESKTOP
                  ;; has Phosh), which beat the plain section there: the
                  ;; Phosh session kept blanking after 60 s (2026-10-30).
                  (for-each
                   (lambda (suffix)
                     (format port "[org.gnome.desktop.session~a]~%idle-delay=uint32 ~a~%~%[org.gnome.desktop.screensaver~a]~%lock-enabled=~a~%lock-delay=uint32 ~a~%~%"
                             suffix #$blank suffix
                             #$(if lock "true" "false") #$(or lock 0)))
                   '("" ":Phosh"))
                  (format port "[org.gnome.desktop.interface]~%color-scheme='~a'~%gtk-theme='~a'~%"
                          #$scheme
                          #$(if (string=? scheme "prefer-dark")
                                "Adwaita-dark"
                                "Adwaita"))))))))
      (home-page "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
      (synopsis "Pro1X blank and lock delays, colour scheme")
      (description "GSettings defaults for the blank and lock delays and the
light or dark colour scheme.")
      (license license:gpl3+))))

(define pro1x-hardware-service-type
  (service-type
   (name 'pro1x-hardware)
   (extensions
    (list
     ;; udev rules: dma-buf, haptics, slider symlink, optional touch matrix
     ;; udev only reads lib/udev/rules.d/ inside each item: a bare rules
     ;; file is silently ignored, hence file->udev-rule.
     (service-extension udev-service-type
                        (lambda (config)
                          (list (file->udev-rule "60-pro1x.rules"
                                                 (pro1x-udev-rules config))
                                (file->udev-rule
                                 "90-pro1x-feedbackd-led.rules"
                                 pro1x-feedbackd-led-rules))))
     ;; /etc/pro1x/dim.conf, /etc/pro1x/charge.conf
     (service-extension etc-service-type pro1x-hardware-etc)
     ;; Phosh's blank and lock delays; notification LED colours
     (service-extension profile-service-type
                        (lambda (config)
                          (cons (pro1x-idle-gsettings config)
                                (pro1x-feedbackd-theme config))))
     ;; feedbackd group (vibration motor)
     (service-extension account-service-type
                        pro1x-hardware-account-groups)
     ;; clock from the RTC (pro1x-clock)
     (service-extension shepherd-root-service-type
                        (lambda (config)
                          (append (pro1x-clock-shepherd-service config)
                                  (pro1x-doubletap-shepherd-service config)
                                  (pro1x-pocket-shepherd-service config)
                                  (pro1x-charge-limit-shepherd-service
                                   config)
                                  (pro1x-torch-guard-shepherd-service
                                   config)
                                  (pro1x-charge-led-shepherd-service
                                   config))))))
   (default-value (pro1x-hardware-configuration))
   (description "Core hardware support for the F(x)tec Pro1X: udev rules for
cameras, haptics, GPIO slider, and optional touch calibration for display gaps.")))
