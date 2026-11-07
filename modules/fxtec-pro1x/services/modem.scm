;;; fxtec-pro1x/services/modem.scm — tqftpserv + rmtfs + ModemManager
;;; Translates modules/modem.nix.

(define-module (fxtec-pro1x services modem)
  #:use-module (fxtec-pro1x packages misc)
  #:use-module (gnu packages base)          ; coreutils, grep
  #:use-module (gnu packages bash)          ; bash-minimal
  #:use-module (gnu packages curl)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages linux)         ; util-linux (mount)
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
  (verbose? pro1x-modem-verbose? (default #f))
  ;; VoLTE: 81voltd serves the IMS data connection the modem asks for.
  (volte? pro1x-modem-volte? (default #t))
  ;; Download GPS orbit data (XTRA, about 50 KB) daily and give it to the
  ;; modem, for faster GPS fixes.
  (xtra? pro1x-modem-xtra? (default #t)))

(define (pro1x-modem-shepherd-services config)
  (let ((verbose-flag (if (pro1x-modem-verbose? config) '("-v") '())))
    (append
     (list

     ;; tqftpserv: deliver modem firmware over QRTR.  It looks for a file
     ;; first next to modem.mbn under firmware_class.path (the store), then
     ;; under its patched base, /run/tqftpserv-fw, where pro1x-modem-pr puts
     ;; the modem partition's modem_pr.
     (shepherd-service
      (provision '(tqftpserv))
      (requirement '(udev pro1x-modem-pr))
      (documentation "TFTP server for Qualcomm modem firmware (QRTR)")
      (start
       #~(make-forkexec-constructor
          (list #$(file-append tqftpserv "/bin/tqftpserv")
                #$@(if (pro1x-modem-verbose? config) '("-v") '()))
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
      (respawn? #t)))
     (if (pro1x-modem-volte? config)
         (list (pro1x-81voltd-service config) pro1x-volte-watch-service)
         '()))))

;;; 81voltd: the modem's IMS stack asks the host, over QRTR (service 770), to
;;; open its IMS data connection; 81voltd opens it through ModemManager (APN
;;; "ims" on Free, chosen by the modem).  Without it, incoming calls on Free
;;; 4G rang about one time in three; with it, 8 of 8 rang over VoLTE, audio
;;; both ways in 7 (2026-11-05, run by hand).  Stopping it leaves the IMS
;;; bearer up (81voltd's README).
(define (pro1x-81voltd-service config)
  (shepherd-service
   (provision '(81voltd))
   (requirement '(modem-manager))
   (documentation "IMS data service for the modem's VoLTE (81voltd)")
   (start
    #~(make-forkexec-constructor
       (list #$(file-append pro1x-81voltd "/bin/81voltd"))
       #:environment-variables
       '#$(if (pro1x-modem-verbose? config) '("G_MESSAGES_DEBUG=all") '())
       #:log-file "/var/log/81voltd.log"))
   (stop #~(make-kill-destructor))
   (respawn? #t)))

;;; After a stay on 3G (an outgoing call fell back there), the modem closed
;;; the IMS bearer and, back on 4G, 81voltd opened no new one: calls went to
;;; voicemail again, until a restart of 81voltd, which brought it back at once
;;; (2026-11-05).  So: on 4G for 30 s without a connected bearer on the "ims"
;;; APN, delete the dead IMS bearers and restart 81voltd.  Waits 90 s after a
;;; restart, twice as long after each one that did not help (at most 30 min),
;;; for networks without VoLTE.
(define pro1x-volte-watch-script
  (program-file
   "pro1x-volte-watch"
   #~(begin
       (setenv "PATH" "/run/current-system/profile/bin")
       (execl #$(file-append bash-minimal "/bin/sh") "sh" "-c" "
kv() { sed -n \"s/^$1 *: //p\"; }
miss=0 wait=90
while :; do
  sleep 10
  m=$(mmcli -m any --output-keyvalue 2>/dev/null) || { miss=0; continue; }
  printf '%s\\n' \"$m\" 2>/dev/null | grep -q '^modem.generic.access-technologies.value.*: lte' || { miss=0; continue; }
  up= stale=
  for b in $(echo \"$m\" | sed -n 's/^modem.generic.bearers.value[^:]*: *//p'); do
    k=$(mmcli -b \"$b\" --output-keyvalue 2>/dev/null)
    [ \"$(echo \"$k\" | kv bearer.properties.apn)\" = ims ] || continue
    if [ \"$(echo \"$k\" | kv bearer.status.connected)\" = yes ]; then up=1
    else stale=\"$stale $b\"; fi
  done
  if [ -n \"$up\" ]; then miss=0 wait=90; continue; fi
  miss=$((miss + 1))
  [ $miss -ge 3 ] || continue
  echo \"$(date '+%F %T') on 4G without an IMS bearer: restarting 81voltd (next wait ${wait} s)\"
  for b in $stale; do mmcli -m any --delete-bearer=\"$b\" >/dev/null 2>&1; done
  herd restart 81voltd >/dev/null 2>&1
  sleep $wait
  wait=$((wait * 2)); [ $wait -le 1800 ] || wait=1800
  miss=0
done"))))

(define pro1x-volte-watch-service
  (shepherd-service
   (provision '(pro1x-volte-watch))
   (requirement '(81voltd))
   (documentation "Restart 81voltd when 4G has no IMS bearer")
   (start
    #~(make-forkexec-constructor
       (list #$pro1x-volte-watch-script)
       #:log-file "/var/log/pro1x-volte-watch.log"))
   (stop #~(make-kill-destructor))
   (respawn? #t)))

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

;;; The modem asks over QRTR TFTP, at every start, for its MCFG files
;;; (/readonly/firmware/image/modem_pr/mcfg/configs/mcfg_hw/mbn_hw.dig and
;;; mcfg_sw/mbn_sw.dig, then the configurations they list).  Android mounts
;;; the modem partition at /vendor/firmware_mnt; without the files the modem
;;; runs on built-in defaults: calls and data work, but GNSS hears no
;;; satellite (moWerk's SailfishOS port, notes/gnss.md, 2026-10-30; here
;;; tqftpserv logged "unable to open .../mbn_hw.dig (2), reject" at every
;;; boot).  This mounts modem_a read-only (both slots carry the same
;;; MPSS.HA.1.1-00140 as the modem.mbn the port loads) and links its
;;; image/modem_pr next to modem.mbn under tqftpserv's base.  Read-only:
;;; nothing writes to the partition.  Exits 0 in every case, so the modem
;;; still starts without it.
;;;
;;; State: not yet booted with it.
(define pro1x-modem-pr-script
  (mixed-text-file
   "pro1x-modem-pr"
   "#!" (file-append bash-minimal "/bin/sh") "
PATH=" coreutils "/bin:" util-linux "/bin
log() { echo \"pro1x-modem-pr: $*\"; }
part=/dev/disk/by-partlabel/modem_a mnt=/run/pro1x-modem-part
dir=/run/tqftpserv-fw/qcom/sm6115/Fxtec/QX1050
mkdir -p \"$mnt\" \"$dir\"
mountpoint -q \"$mnt\" ||
  mount -t vfat -o ro,nodev,nosuid,noexec \"$part\" \"$mnt\" ||
  { log \"mounting $part failed\"; exit 0; }
if [ -d \"$mnt/image/modem_pr\" ]; then
  ln -sfn \"$mnt/image/modem_pr\" \"$dir/modem_pr\"
  log \"modem_pr served from $part\"
else
  log \"no image/modem_pr on $part\"
fi
exit 0
"))

(define (pro1x-modem-pr-service config)
  (shepherd-service
   (provision '(pro1x-modem-pr))
   (requirement '(udev))
   (documentation "Serve the modem partition's MCFG files to tqftpserv")
   (one-shot? #t)
   (start #~(make-forkexec-constructor
             (list "/bin/sh" #$pro1x-modem-pr-script)
             #:log-file "/var/log/pro1x-modem-pr.log"))
   (stop #~(make-kill-destructor))))

;;; The modem's GNSS engine comes up locked (NV 452 gps1_lock = 3: MI and
;;; MT).  Android's location HAL unlocks it; without that every location
;;; session stays silent.  rmtfs runs with -r, so the modem's NV writes stay
;;; in RAM and the unlock is redone at every boot.  ModemManager's GPS reads
;;; NMEA, and its own "setup NMEA traces" times out on this modem (the Get
;;; NMEA Types indication arrives before the response), so the NMEA types
;;; are set here too.  From the NixOS port (nyymi609/fxtec-pro1x-nixos,
;;; commit bb65696, modules/modem.nix).  Exits 0 in every case.
;;;
;;; State: both QMI requests accepted on this phone, by hand (2026-11-06).
(define pro1x-gnss-unlock-script
  (let ((qmicli (file-append libqmi-1.36 "/bin/qmicli")))
    (mixed-text-file
     "pro1x-gnss-unlock"
     "#!" (file-append bash-minimal "/bin/sh") "
PATH=" coreutils "/bin:" grep "/bin:" libqrtr "/bin
log() { echo \"pro1x-gnss-unlock: $*\"; }
# The location service (16) shows up on QRTR a while after the modem starts.
i=0
while [ $i -lt 120 ]; do
  qrtr-lookup | grep -q '^ *16 .* 0 ' && break
  i=$((i + 1)); sleep 2
done
i=0
while [ $i -lt 5 ]; do
  " qmicli " -d qrtr://0 --loc-set-engine-lock=none &&
    " qmicli " -d qrtr://0 --loc-set-nmea-types='gga|rmc|gsv|gsa|vtg' &&
    { log 'GNSS engine unlocked, NMEA types set'; exit 0; }
  i=$((i + 1)); sleep 5
done
log 'unlocking the GNSS engine failed'
exit 0
")))

(define (pro1x-gnss-unlock-service config)
  (shepherd-service
   (provision '(pro1x-gnss-unlock))
   (requirement '(rmtfs))
   (documentation "Unlock the modem's GNSS engine")
   (one-shot? #t)
   (start #~(make-forkexec-constructor
             (list "/bin/sh" #$pro1x-gnss-unlock-script)
             #:log-file "/var/log/pro1x-gnss-unlock.log"))
   (stop #~(make-kill-destructor))))

;;; XTRA, the modem's predicted satellite orbits: without them a first fix
;;; waited for each satellite's own orbit data (about 7 minutes outdoors,
;;; 2026-11-07).  ModemManager lists the servers the modem names (needs
;;; device/patches/modem-manager-loc-indication-first.patch: the modem
;;; answers before ModemManager listened) and injects the file; the modem
;;; keeps it valid for 168 h.  The modem's writes do not outlive a boot
;;; (rmtfs -r), so the file is kept in /var/lib/pro1x-xtra and injected at
;;; each start; downloaded again once a day, from the first server that
;;; answers, over whatever network is up; on failure, an hour later.
;;;
;;; State: one injection by hand on the phone (2026-11-07, a patched
;;; ModemManager run by hand): "successfully injected", validity 168 h.
;;; The service: build-tested only.
(define pro1x-xtra-script
  (mixed-text-file
   "pro1x-xtra"
   "#!" (file-append bash-minimal "/bin/sh") "
PATH=" coreutils "/bin:" findutils "/bin:" grep "/bin:" sed "/bin:" curl "/bin:" modem-manager-1.24 "/bin
dir=/var/lib/pro1x-xtra file=/var/lib/pro1x-xtra/xtra.bin
log() { echo \"$(date '+%F %T') $*\"; }
servers() {
  mmcli -m any --location-status --output-keyvalue 2>/dev/null |
    sed -n 's/^modem.location.gps.assistance-servers.value[^:]*: *//p'
}
inject() {
  if mmcli -m any --location-inject-assistance-data=\"$file\" >/dev/null 2>&1; then
    log \"injected ($(stat -c %s \"$file\") bytes, from $(date -r \"$file\" '+%F %T'))\"
  else
    log 'injection failed'; return 1
  fi
}
download() {
  for url in $(servers); do
    curl -sfL -m 120 -o \"$file.new\" \"$url\" && [ -s \"$file.new\" ] &&
      mv \"$file.new\" \"$file\" && { log \"downloaded $url\"; return 0; }
  done
  rm -f \"$file.new\"; log 'download failed'; return 1
}
mkdir -p \"$dir\"
# ModemManager lists the servers once the modem is up.
until [ -n \"$(servers)\" ]; do sleep 30; done
# The cached file, if under 7 days old.
[ -n \"$(find \"$file\" -mmin -10080 2>/dev/null)\" ] && inject
while :; do
  if [ -z \"$(find \"$file\" -mmin -1440 2>/dev/null)\" ]; then
    if download && inject; then sleep 86400; else sleep 3600; fi
  else
    sleep 3600
  fi
done
"))

(define (pro1x-xtra-service config)
  (shepherd-service
   (provision '(pro1x-xtra))
   (requirement '(modem-manager))
   (documentation "Keep the modem's XTRA satellite orbit data fresh")
   (start #~(make-forkexec-constructor
             (list "/bin/sh" #$pro1x-xtra-script)
             #:log-file "/var/log/pro1x-xtra.log"))
   (stop #~(make-kill-destructor))
   (respawn? #t)))

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
                                  (list (pro1x-uim-provision-service config)
                                        (pro1x-gnss-unlock-service config)
                                        (pro1x-modem-pr-service config))
                                  (if (pro1x-modem-xtra? config)
                                      (list (pro1x-xtra-service config))
                                      '())
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
