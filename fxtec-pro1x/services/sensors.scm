;;; fxtec-pro1x/services/sensors.scm — ADSP sensors via hexagonrpcd + iio-sensor-proxy
;;; Translates modules/sensors.nix.

(define-module (fxtec-pro1x services sensors)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages freedesktop) ; iio-sensor-proxy
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services dbus)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-sensors-configuration
            pro1x-sensors-configuration?
            make-pro1x-sensors-configuration
            pro1x-sensors-service-type))

(define-record-type* <pro1x-sensors-configuration>
  pro1x-sensors-configuration make-pro1x-sensors-configuration
  pro1x-sensors-configuration?
  ;; Path to the hexagonfs tree (sensors/config, sensors/registry, sensors/sns_reg.conf)
  (hexagonfs        pro1x-sensors-hexagonfs
                    (default (local-file "../../device/hexagonfs"
                                         "hexagonfs" #:recursive? #t)))
  ;; Start at boot?
  (autostart?       pro1x-sensors-autostart?       (default #t))
  ;; Platform properties the ADSP asks for by name
  (properties       pro1x-sensors-properties
                    (default '(("hw_platform" . "QRD"))))
  ;; Sensor mount matrix for iio-sensor-proxy
  (accel-mount-matrix pro1x-sensors-accel-mount-matrix
                      (default "-1, 0, 0; 0, -1, 0; 0, 0, 1"))
  ;; Disable ADSP auto-recovery to prevent crash loops
  (disable-recovery? pro1x-sensors-disable-recovery? (default #t))
  ;; hexagonrpcd package (allows version override)
  (hexagonrpcd-package pro1x-sensors-hexagonrpcd-package
                       (default hexagonrpcd)))

(define %state-dir "/var/lib/hexagonrpcd")

(define (pro1x-sensors-prepare-script config)
  (let* ((hexfs   (pro1x-sensors-hexagonfs config))
         (props   (pro1x-sensors-properties config))
         (disable (pro1x-sensors-disable-recovery? config))
         (prop-writes
          (apply string-append
                 (map (lambda (kv)
                        (string-append
                         "printf '%s\\n' "
                         (string-append "'" (cdr kv) "'")
                         " > " %state-dir "/properties/" (car kv) "\n"))
                      props))))
    (computed-file "pro1x-hexagonrpcd-prepare"
      #~(call-with-output-file #$output
          (lambda (port)
            (display "#!/bin/sh\nset -eu\n" port)
            (display (string-append "d=" #$%state-dir "\n") port)
            (display "mkdir -p \"$d/sensors\"\n" port)
            ;; Refresh static config on every start
            (display "rm -rf \"$d/sensors/config\"\n" port)
            (display (string-append "cp -r " #$hexfs "/sensors/config \"$d/sensors/config\"\n") port)
            (display (string-append "cp -f " #$hexfs "/sensors/sns_reg.conf \"$d/sensors/sns_reg.conf\"\n") port)
            ;; DSP modules
            (display "rm -rf \"$d/dsp\"\n" port)
            (display (string-append "[ -d " #$hexfs "/dsp ] && cp -r " #$hexfs "/dsp \"$d/dsp\" || true\n") port)
            ;; Writable registry: seed from store if stale
            (display "rm -rf \"$d/sensors/registry\"\n" port)
            (display "reg=\"$d/sensors/persist/registry\"\n" port)
            (display (string-append
                      "if [ \"$(cat \"$d/.seeded-from\" 2>/dev/null)\" != \"" #$hexfs "\" ] || [ ! -d \"$reg/registry\" ]; then\n") port)
            (display "  rm -rf \"$d/sensors/persist\"\n" port)
            (display "  mkdir -p \"$reg\"\n" port)
            (display (string-append "  cp -r " #$hexfs "/sensors/registry/. \"$reg/registry/\"\n") port)
            (display (string-append "  echo '" #$hexfs "' > \"$d/.seeded-from\"\n") port)
            (display "fi\n" port)
            (display "chmod -R u+rwX \"$d\"\n" port)
            ;; Platform properties
            (display "rm -rf \"$d/properties\"; mkdir -p \"$d/properties\"\n" port)
            (display #$prop-writes port)
            ;; /sys/devices/soc0 socinfo symlink
            (display "ln -sfn /sys/devices/soc0 \"$d/socinfo\"\n" port)
            ;; Optionally disable ADSP recovery
            #$@(if disable
                   (list
                    #~(display
                       "for rp in /sys/class/remoteproc/*; do\n  [ \"$(cat \"$rp/name\" 2>/dev/null)\" = adsp ] && echo disabled > \"$rp/recovery\" || true\ndone\n"
                       port))
                   '())
            ;; Wait for fastrpc-adsp
            (display "i=0\nwhile [ \"$i\" -lt 240 ]; do\n  [ -e /dev/fastrpc-adsp ] && exit 0\n  i=$((i+1)); sleep 1\ndone\necho '/dev/fastrpc-adsp not found' >&2; exit 1\n" port)
            (chmod #$output #o755))))))

(define (pro1x-sensors-shepherd-services config)
  (let* ((pkg      (pro1x-sensors-hexagonrpcd-package config))
         (auto?    (pro1x-sensors-autostart? config))
         (prepare  (pro1x-sensors-prepare-script config)))
    (list
     (shepherd-service
      (provision '(pro1x-hexagonrpcd))
      (requirement '(udev))
      (documentation "hexagonrpcd: serve ADSP sensor config over FastRPC")
      (auto-start? auto?)
      (start
       #~(lambda args
           (system* #$prepare)
           ((make-forkexec-constructor
             (list #$(file-append pkg "/bin/hexagonrpcd")
                   "-f" "/dev/fastrpc-adsp"
                   "-d" "adsp"
                   "-s"
                   "-R" #$%state-dir)
             #:log-file "/var/log/hexagonrpcd.log") args)))
      (stop #~(make-kill-destructor))
      (respawn? #t)))))

(define (pro1x-sensors-udev-rules config)
  (let ((matrix (pro1x-sensors-accel-mount-matrix config)))
    (list
     (computed-file "90-pro1x-sensors.rules"
       #~(call-with-output-file #$output
           (lambda (port)
             (display
              (string-append
               "SUBSYSTEM==\"misc\", KERNEL==\"fastrpc-*\","
               " ENV{ACCEL_MOUNT_MATRIX}+=\"" #$matrix "\"\n"
               "SUBSYSTEM==\"misc\", KERNEL==\"fastrpc-adsp\","
               " ENV{IIO_SENSOR_PROXY_TYPE}+=\"ssc-accel ssc-proximity\"\n")
              port)))))))

(define (pro1x-sensors-packages config)
  (list iio-sensor-proxy
        (pro1x-sensors-hexagonrpcd-package config)))

(define pro1x-sensors-service-type
  (service-type
   (name 'pro1x-sensors)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-sensors-shepherd-services)
     (service-extension udev-service-type
                        pro1x-sensors-udev-rules)
     (service-extension dbus-root-service-type
                        (lambda (config) (list iio-sensor-proxy)))
     (service-extension profile-service-type
                        pro1x-sensors-packages)))
   (default-value (pro1x-sensors-configuration))
   (description "ADSP (SSC) sensors for the Pro1X via hexagonrpcd and iio-sensor-proxy.
Provides accelerometer, gyroscope, proximity and ambient light sensors to
compositors like Phosh.  Requires sensor config files from device/hexagonfs/.")))
