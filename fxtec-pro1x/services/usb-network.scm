;;; fxtec-pro1x/services/usb-network.scm — Ethernet over USB CDC gadget
;;; Translates modules/usb-network.nix.
;;;
;;; The phone appears on the PC as a serial port + Ethernet adapter (g_cdc).
;;; Static IP 172.16.42.1/24 with DHCP server, fixed MAC addresses so the
;;; interface name on the PC side is stable across reboots.
;;;
;;; After connecting:
;;;   ssh user@172.16.42.1
;;;   guix deploy ...

(define-module (fxtec-pro1x services usb-network)
  #:use-module (gnu packages dns)
  #:use-module (gnu packages linux)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (pro1x-usb-network-configuration
            pro1x-usb-network-configuration?
            make-pro1x-usb-network-configuration
            pro1x-usb-network-service-type))

(define-record-type* <pro1x-usb-network-configuration>
  pro1x-usb-network-configuration make-pro1x-usb-network-configuration
  pro1x-usb-network-configuration?
  (address pro1x-usb-network-address (default "172.16.42.1"))
  (prefix  pro1x-usb-network-prefix  (default 24)))

;;; A Shepherd service that:
;;;   1. Waits for usb0 to appear
;;;   2. Sets the static IP
;;;   3. Starts dnsmasq as DHCP server on usb0
(define (pro1x-usb-network-shepherd-services config)
  (let* ((addr   (pro1x-usb-network-address config))
         (prefix (pro1x-usb-network-prefix config))
         (cidr   (string-append addr "/" (number->string prefix)))
         ;; DHCP pool: .10 – .19
         (pool-start (string-append
                      (string-join (list-head (string-split addr #\.) 3) ".")
                      ".10"))
         (pool-end   (string-append
                      (string-join (list-head (string-split addr #\.) 3) ".")
                      ".19")))
    (list
     (shepherd-service
      (provision '(pro1x-usb-network))
      (requirement '(networking udev))
      (documentation "USB CDC gadget network: 172.16.42.1/24 + DHCP for the PC")
      (start
       #~(make-forkexec-constructor
          (list "/bin/sh" "-c"
                (string-append
                 ;; Wait up to 30s for usb0
                 "i=0; while [ $i -lt 30 ]"
                 " && ! " #$(file-append iproute "/sbin/ip")
                 " link show usb0 >/dev/null 2>&1"
                 "; do sleep 1; i=$((i+1)); done; "
                 #$(file-append iproute "/sbin/ip")
                 " link set usb0 up; "
                 #$(file-append iproute "/sbin/ip")
                 " addr add " #$cidr " dev usb0 || true; "
                 ;; dnsmasq for DHCP only on usb0
                 #$(file-append dnsmasq "/sbin/dnsmasq")
                 " --no-daemon"
                 " --interface=usb0"
                 " --bind-interfaces"
                 " --no-resolv"
                 " --no-hosts"
                 " --dhcp-leasefile=/tmp/dnsmasq-usb.leases"
                 " --dhcp-option=3"
                 " --dhcp-range=" #$pool-start "," #$pool-end ",12h"))
          #:log-file "/var/log/pro1x-usb-network.log"))
      (stop #~(make-kill-destructor))
      (respawn? #t)))))

(define pro1x-usb-network-service-type
  (service-type
   (name 'pro1x-usb-network)
   (extensions
    (list
     (service-extension shepherd-root-service-type
                        pro1x-usb-network-shepherd-services)))
   (default-value (pro1x-usb-network-configuration))
   (description "USB gadget Ethernet (usb0) with static IP and DHCP server.
Allows SSH and guix deploy over USB.  The kernel must load g_cdc, configured
via kernel parameters g_cdc.host_addr= / g_cdc.dev_addr=.")))
