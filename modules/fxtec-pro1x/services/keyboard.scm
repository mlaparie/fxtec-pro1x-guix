;;; fxtec-pro1x/services/keyboard.scm — keyd + XKB layout + dconf persistence
;;; + keyboard backlight
;;;
;;; pro1x-kbd-backlight lights the keyboard (LED white:kbd_backlight, on/off)
;;; while the keyboard is slid out (SW_KEYPAD_SLIDE = 1 on the gpio-keys
;;; device) and the panel is on (DRM connector dpms, which follows sway's
;;; and phoc's output power).  dpms is a cached kernel value; reading it does
;;; not touch the DSI link, unlike backlight actual_brightness.  The LED is
;;; written only when that result changes, so a manual change
;;; (brightnessctl -d white:kbd_backlight set 0) holds until the next slide
;;; or panel change.  Sliding the keyboard out with the panel off turns
;;; the panel on in every running sway (swaymsg on its IPC socket); sway's
;;; bindswitch knows only lid and tablet switches.  Not done for Phosh yet.
;;;
;;; It also turns off after BACKLIGHT-TIMEOUT seconds without a key press
;;; (default 60, #f for never), and on again at the next key, slide-out or
;;; panel-on.  Key presses are read from keyd's virtual keyboard: keyd grabs
;;; the real one.  In config.scm:
;;;   (modify-services (operating-system-user-services base)
;;;     (pro1x-keyboard-service-type
;;;      config => (pro1x-keyboard-configuration
;;;                 (inherit config) (backlight-timeout 120))))
;;;
;;; State: slide in/out and the power key follow the LED (2026-10-28,
;;; generation 4); panel wake on slide-out not tested yet; the timeout is
;;; build-tested only (2026-10-30).

(define-module (fxtec-pro1x services keyboard)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages gnome)         ; dconf
  #:use-module (gnu packages linux)         ; keyd, evtest
  #:use-module (gnu packages wm)            ; sway (swaymsg)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services configuration)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-keyboard-configuration
            pro1x-keyboard-configuration?
            make-pro1x-keyboard-configuration
            pro1x-keyboard-service-type))

(define-record-type* <pro1x-keyboard-configuration>
  pro1x-keyboard-configuration make-pro1x-keyboard-configuration
  pro1x-keyboard-configuration?
  (xkb-layout  pro1x-keyboard-xkb-layout  (default "us"))
  (xkb-variant pro1x-keyboard-xkb-variant (default "intl"))
  ;; Seconds without a key press before the keyboard light goes off; #f:
  ;; never (the light then follows only the slider and the panel).
  (backlight-timeout pro1x-keyboard-backlight-timeout (default 60)))

;;; /etc/keyd/default.conf
(define (pro1x-keyboard-etc config)
  (let* ((layout  (pro1x-keyboard-xkb-layout  config))
         (variant (pro1x-keyboard-xkb-variant config))
         ;; dconf xkb source: "us+intl" when variant present, else just "us"
         (xkb-source (if (string-null? variant)
                         layout
                         (string-append layout "+" variant))))
    (list
     `("keyd/default.conf"
       ,(local-file (repository-file "device/input/keyd.conf") "keyd.conf"))
     ;; dconf system-db that persists the XKB layout across reboots.
     `("dconf/profile/user"
       ,(plain-file "dconf-profile-user"
                    "user-db:user\nsystem-db:local\n"))
     ;; Compiled here: /etc/dconf is a read-only store link, so
     ;; `dconf update' at activation cannot write /etc/dconf/db/local.
     `("dconf/db/local"
       ,(pro1x-dconf-db
         "dconf-db-local"
         (plain-file "00-keyboard"
                     (string-append
                      "[org/gnome/desktop/input-sources]\n"
                      "sources=[('xkb', '" xkb-source "')]\n")))))))

;;; Compile the dconf keyfile KEYFILE into a GVariant database, like
;;; dconf-profile->db in (gnu services xorg).
(define (pro1x-dconf-db name keyfile)
  (computed-file
   name
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils))
         (mkdir "keyfiles")
         (symlink #$keyfile "keyfiles/00-keyfile")
         (invoke #$(file-append dconf "/bin/dconf") "compile"
                 #$output "keyfiles")))))

;;; Keyboard backlight: on while slid out, the panel is on and a key was
;;; pressed less than TIMEOUT seconds ago.
(define (pro1x-kbd-backlight-program timeout)
  (program-file
   "pro1x-kbd-backlight"
   #~(begin
       (use-modules (ice-9 binary-ports)
                    (ice-9 ftw)
                    (ice-9 match)
                    (ice-9 rdelim)
                    (rnrs bytevectors)
                    (srfi srfi-1))

       (define slider "/dev/input/pro1x-slider")
       (define led "/sys/class/leds/white:kbd_backlight/brightness")
       (define ev-sw 5)
       (define sw-keypad-slide 10)

       ;; `evtest --query' exits with 10 when the switch is set.
       (define (slider-open?)
         (= 10 (status:exit-val
                (system* #$(file-append evtest "/bin/evtest") "--query"
                         slider "EV_SW" "SW_KEYPAD_SLIDE"))))

       (define (panel-on?)
         (any-dsi-on? (or (scandir "/sys/class/drm"
                                   (lambda (f) (string-contains f "-DSI-")))
                          '())))

       (define (any-dsi-on? connectors)
         (match connectors
           (() #f)
           ((c rest ...)
            (or (string=? "On"
                          (call-with-input-file
                              (string-append "/sys/class/drm/" c "/dpms")
                            read-line))
                (any-dsi-on? rest)))))

       ;; Sway does not see the slide switch: turn its outputs on.
       (define (wake-sway!)
         (for-each
          (lambda (dir)
            (for-each
             (lambda (sock)
               (setenv "SWAYSOCK" (string-append dir "/" sock))
               (system* #$(file-append sway "/bin/swaymsg")
                        "output * power on"))
             (or (scandir dir (lambda (f) (string-prefix? "sway-ipc." f)))
                 '())))
          (map (lambda (uid) (string-append "/run/user/" uid))
               (or (scandir "/run/user"
                            (lambda (f) (not (string-prefix? "." f))))
                   '()))))

       (define (set-led! value)
         (call-with-output-file led
           (lambda (port) (display value port))))

       (define timeout #$timeout)
       (define ev-key 1)

       ;; keyd's virtual keyboard, where key presses arrive (keyd grabs the
       ;; real keyboard).  #f until keyd has created it.
       (define (open-keyboard)
         (let ((event (find (lambda (e)
                              (false-if-exception
                               (string=? "keyd virtual keyboard"
                                         (call-with-input-file
                                             (string-append
                                              "/sys/class/input/" e
                                              "/device/name")
                                           read-line))))
                            (or (scandir "/sys/class/input"
                                         (lambda (f)
                                           (string-prefix? "event" f)))
                                '()))))
           (and event
                (false-if-exception
                 (let ((port (open-input-file
                              (string-append "/dev/input/" event)
                              #:binary #t)))
                   (setvbuf port 'none)
                   port)))))

       (define (read-event port)
         ;; struct input_event on aarch64: 16-byte timeval, u16 type,
         ;; u16 code, s32 value.  #f at end of file (device gone).
         (let ((event (get-bytevector-n port 24)))
           (and (bytevector? event) (= 24 (bytevector-length event))
                event)))

       (let ((port (open-input-file slider #:binary #t)))
         (setvbuf port 'none)
         ;; ACTIVE: time of the last key press, slide-out or panel-on.
         (let loop ((open? (slider-open?)) (last #f) (keyboard #f)
                    (active (current-time)) (panel? (panel-on?)))
           (let* ((keyboard (or keyboard (open-keyboard)))
                  (panel-now? (panel-on?))
                  (active (if (and panel-now? (not panel?))
                              (current-time)
                              active))
                  (recent? (or (not timeout)
                               (< (- (current-time) active) timeout)))
                  (value (if (and open? panel-now? recent?) "1" "0")))
             (unless (equal? value last)
               (set-led! value))
             ;; Poll dpms and the timeout once a second meanwhile.
             (match (select (if keyboard (list port keyboard) (list port))
                            '() '() 1)
               ((ready () ())
                (cond
                 ((and keyboard (memq keyboard ready))
                  (let ((event (read-event keyboard)))
                    (cond
                     ((not event)
                      (close-port keyboard)
                      (loop open? value #f active panel-now?))
                     ((and (= ev-key (bytevector-u16-native-ref event 16))
                           (= 1 (bytevector-s32-native-ref event 20)))
                      (loop open? value keyboard (current-time) panel-now?))
                     (else
                      (loop open? value keyboard active panel-now?)))))
                 ((memq port ready)
                  (let* ((event (get-bytevector-n port 24))
                         (open-now?
                          (if (and (= ev-sw (bytevector-u16-native-ref event 16))
                                   (= sw-keypad-slide
                                      (bytevector-u16-native-ref event 18)))
                              (= 1 (bytevector-s32-native-ref event 20))
                              open?)))
                    (when (and open-now? (not open?) (not panel-now?))
                      (wake-sway!))
                    (loop open-now? value keyboard
                          (if (and open-now? (not open?))
                              (current-time)
                              active)
                          panel-now?)))
                 (else (loop open? value keyboard active panel-now?))))
               (_ (loop open? value keyboard active panel-now?)))))))))

;;; Shepherd services: keyd, keyboard backlight
(define (pro1x-keyboard-shepherd-services config)
  (list
   (shepherd-service
    (provision '(pro1x-kbd-backlight))
    (requirement '(udev keyd))
    (documentation "Keyboard backlight on while slid out, the panel is on
and a key was pressed recently.")
    (start #~(make-forkexec-constructor
              (list #$(pro1x-kbd-backlight-program
                       (pro1x-keyboard-backlight-timeout config)))
              #:log-file "/var/log/pro1x-kbd-backlight.log"))
    (stop #~(make-kill-destructor))
    (respawn? #t))
   (shepherd-service
    (provision '(keyd))
    (requirement '(udev))
    (documentation "keyd — keyboard Fn-layer remapping for the Pro1X")
    (start
     #~(make-forkexec-constructor
        (list #$(file-append keyd "/bin/keyd"))
        #:log-file "/var/log/keyd.log"))
    (stop #~(make-kill-destructor))
    (respawn? #t))))

(define (pro1x-keyboard-packages config)
  (list keyd dconf))

(define pro1x-keyboard-service-type
  (service-type
   (name 'pro1x-keyboard)
   (extensions
    (list
     (service-extension etc-service-type          pro1x-keyboard-etc)
     (service-extension shepherd-root-service-type pro1x-keyboard-shepherd-services)
     (service-extension profile-service-type       pro1x-keyboard-packages)))
   (default-value (pro1x-keyboard-configuration))
   (description "Hardware keyboard support for the F(x)tec Pro1X: keyd Fn-layer
remapping, XKB layout, dconf system-db so the layout survives reboots, and the
keyboard backlight.")))
