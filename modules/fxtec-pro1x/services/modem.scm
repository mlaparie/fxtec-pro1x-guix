;;; fxtec-pro1x/services/modem.scm — tqftpserv + rmtfs + ModemManager
;;; Translates modules/modem.nix.

(define-module (fxtec-pro1x services modem)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages base)          ; coreutils, grep
  #:use-module (gnu packages bash)          ; bash-minimal
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages telephony)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services dbus)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-modem-configuration
            pro1x-modem-configuration?
            make-pro1x-modem-configuration
            pro1x-modem-service-type))

(define-record-type* <pro1x-modem-configuration>
  pro1x-modem-configuration make-pro1x-modem-configuration
  pro1x-modem-configuration?
  (verbose? pro1x-modem-verbose? (default #f)))

(define (pro1x-modem-shepherd-services config)
  (let ((verbose-flag (if (pro1x-modem-verbose? config) '("-v") '())))
    (list

     ;; tqftpserv: deliver modem firmware over QRTR.
     ;; The binary is patched to look for firmware at /run/current-system/firmware.
     ;; Guix's activate-firmware sets firmware_class.path in sysfs but does not
     ;; create that symlink; we create it here at service-start time, after the
     ;; activation scripts have already run.
     (shepherd-service
      (provision '(tqftpserv))
      (requirement '(udev))
      (documentation "TFTP server for Qualcomm modem firmware (QRTR)")
      (start
       #~(make-forkexec-constructor
          (list "/bin/sh" "-c"
                (string-append
                 "fw=$(cat /sys/module/firmware_class/parameters/path 2>/dev/null);"
                 "[ -n \"$fw\" ] && [ ! -e /run/current-system/firmware ]"
                 " && ln -sf \"$fw\" /run/current-system/firmware;"
                 "exec " #$(file-append tqftpserv "/bin/tqftpserv")
                 #$(if (pro1x-modem-verbose? config) " -v" "")))
          #:log-file "/var/log/tqftpserv.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t))

     ;; rmtfs: wait for modem remoteproc, then serve EFS partitions
     (shepherd-service
      (provision '(rmtfs))
      (requirement '(udev tqftpserv pro1x-modem-ready))
      (documentation "Qualcomm remote filesystem service (modemst1/2, fsg, fsc)")
      (start
       #~(make-forkexec-constructor
          ;; ExecStartPre: wait up to 180 s for modem remoteproc
          (append (list #$(file-append rmtfs "/bin/rmtfs")
                        "-r" "-P" "-s")
                  '#$verbose-flag)
          #:environment-variables
          '("PATH=/run/current-system/profile/bin")
          #:log-file "/var/log/rmtfs.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t))

     ;; ModemManager: the high-level modem manager.
     ;; Before starting, re-trigger net udev events so rmnet_ipa0 gets tagged
     ;; with ID_MM_PHYSDEV_UID=qcom-soc (race: IPA driver may fire its ADD
     ;; event before our udev rules are installed on first boot).
     (shepherd-service
      (provision '(modem-manager))
      (requirement '(dbus-system tqftpserv rmtfs pro1x-uim-provision))
      (documentation "ModemManager")
      (start
       #~(make-forkexec-constructor
          (list "/bin/sh" "-c"
                (string-append
                 "udevadm trigger --subsystem-match=net --action=add"
                 " && udevadm settle --timeout=5"
                 " && exec " #$(file-append modem-manager-1.24 "/sbin/ModemManager")))
          #:environment-variables '("PATH=/run/current-system/profile/bin")
          #:log-file "/var/log/ModemManager.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t)))))

;;; The SIM's UIM provisioning session, activated before ModemManager.
;;; The modem firmware (MPSS.HA.1.1) does not keep the primary GW
;;; provisioning session across boots: the SIM shows present but stays
;;; "detected" and nothing registers (ModemManager: sim-missing).  Activate
;;; it for the first USIM application on slot 1, every boot, idempotently;
;;; postmarketOS's msm-modem-uim-selection and moWerk's SailfishOS port
;;; (qx1050-modem-prep.sh) do the same.  It must run before ModemManager,
;;; which probes a QRTR modem only once.  Exits 0 in every case so that
;;; ModemManager still starts.
;;;
;;; State: reported working on this phone (NixOS, SailfishOS); not yet run
;;; on Guix.
(define pro1x-uim-provision-script
  (let ((qmicli (file-append libqmi-1.36 "/bin/qmicli")))
    (mixed-text-file
     "pro1x-uim-provision"
     "#!" (file-append bash-minimal "/bin/sh") "
PATH=" coreutils "/bin:" gawk "/bin:" grep "/bin
log() { echo \"pro1x-uim-provision: $*\"; }
status=
i=0
# The UIM service appears on QRTR some seconds after the modem starts.
while [ $i -lt 60 ]; do
  status=$(" qmicli " -d qrtr://0 --uim-get-card-status 2>/dev/null)
  echo \"$status\" | grep -q \"Card state: 'present'\" && break
  i=$((i + 1)); sleep 1
done
echo \"$status\" | grep -q \"Card state: 'present'\" || { log 'no SIM card present (or no UIM service)'; exit 0; }
if echo \"$status\" | grep -q \"Primary GW:.*session doesn't exist\"; then
  aid=$(echo \"$status\" | awk '/Application type:.*usim/ { f = 1 } f && /Application ID:/ { getline; gsub(/[^0-9A-Fa-f]/, \"\"); print; exit }')
  if [ -n \"$aid\" ]; then
    " qmicli " -d qrtr://0 --uim-change-provisioning-session=\"session-type=primary-gw-provisioning,activate=yes,slot=1,aid=$aid\" \\
      && log 'primary GW provisioning session activated' \\
      || log 'activating the provisioning session failed'
  else
    log 'no USIM application on the card'
  fi
else
  log 'primary GW provisioning session already present'
fi
exit 0
")))

(define (pro1x-uim-provision-service config)
  (shepherd-service
   (provision '(pro1x-uim-provision))
   (requirement '(rmtfs))
   (documentation "Activate the SIM's UIM provisioning session")
   (one-shot? #t)
   (start #~(make-forkexec-constructor
             (list "/bin/sh" #$pro1x-uim-provision-script)
             #:log-file "/var/log/pro1x-uim-provision.log"))
   (stop #~(make-kill-destructor))))

;;; polkit: let members of netdev use ModemManager (unlock the SIM with PIN
;;; or PUK, calls, SMS) and NetworkManager.  polkit's defaults allow these
;;; only to the active local session, which it cannot tell without logind
;;; (seatd here): GNOME Settings' SIM unlock was refused ("PolicyKit
;;; authorization failed" from ModemManager) and closed its dialog without
;;; an error, so the SIM stayed locked.
(define pro1x-modem-polkit-rules
  (file-union
   "pro1x-modem-polkit-rules"
   `(("share/polkit-1/rules.d/50-pro1x-netdev.rules"
      ,(plain-file
        "50-pro1x-netdev.rules"
        "polkit.addRule(function (action, subject) {
    if ((action.id.indexOf(\"org.freedesktop.ModemManager1.\") == 0 ||
         action.id.indexOf(\"org.freedesktop.NetworkManager.\") == 0) &&
        subject.isInGroup(\"netdev\")) {
        return polkit.Result.YES;
    }
});
")))))

;;; A one-shot service that blocks rmtfs startup until the modem remoteproc appears.
(define (pro1x-modem-rmtfs-wait config)
  (list
   (shepherd-service
    (provision '(pro1x-modem-ready))
    (requirement '(udev))
    (documentation "Wait for modem remoteproc before starting rmtfs")
    (one-shot? #t)
    (start
     #~(make-forkexec-constructor
        (list #$(computed-file "rmtfs-wait"
                  #~(begin
                      (call-with-output-file #$output
                        (lambda (port)
                          (display "#!/bin/sh\n" port)
                          (display "i=0\n" port)
                          (display "while [ \"$i\" -lt 180 ]; do\n" port)
                          (display "  for n in /sys/class/remoteproc/*/name; do\n" port)
                          (display "    [ -r \"$n\" ] && [ \"$(cat \"$n\")\" = modem ] && exit 0\n" port)
                          (display "  done\n" port)
                          (display "  i=$((i+1)); sleep 1\n" port)
                          (display "done\n" port)
                          (display "echo 'modem remoteproc not found' >&2; exit 1\n" port)))
                      (chmod #$output #o755))))
        #:log-file "/var/log/pro1x-modem-wait.log"))
    (stop #~(make-kill-destructor)))))

(define (pro1x-modem-packages config)
  (list tqftpserv rmtfs modem-manager-1.24))

(define pro1x-modem-service-type
  (service-type
   (name 'pro1x-modem)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        (lambda (config)
                          (append (pro1x-modem-rmtfs-wait config)
                                  (list (pro1x-uim-provision-service config))
                                  (pro1x-modem-shepherd-services config))))
     (service-extension dbus-root-service-type
                        (lambda (_) (list modem-manager-1.24)))
     (service-extension polkit-service-type
                        ;; MM's actions (share/polkit-1/actions): without
                        ;; them every unlock fails, even as root ("Action
                        ;; ...ModemManager1.Device.Control is not registered").
                        (const (list modem-manager-1.24
                                     pro1x-modem-polkit-rules)))
     ;; MM's own rules: 77-mm-qcom-soc.rules tags rmnet_ipa0 (driver ipa)
     ;; with ID_MM_PHYSDEV_UID=qcom-soc; without them MM fails with "Failed
     ;; to find a net port in the QMI modem".
     (service-extension udev-service-type
                        (lambda (_) (list modem-manager-1.24)))
     (service-extension profile-service-type
                        pro1x-modem-packages)))
   (default-value (pro1x-modem-configuration))
   (description "Qualcomm modem userspace for the Pro1X: tqftpserv (firmware),
rmtfs (EFS partitions), and ModemManager.  Wi-Fi firmware also goes through
tqftpserv, so enable this service even without a SIM.")))
