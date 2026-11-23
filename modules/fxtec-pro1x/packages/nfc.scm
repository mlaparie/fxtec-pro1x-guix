;;; fxtec-pro1x/packages/nfc.scm — neard, the NFC daemon
;;;
;;; The Pro¹x's NFC controller (NXP, NCI 2.0) is driven by the kernel's
;;; nxp-nci (pro1x-nfc.patch); neard reads and writes tags through the
;;; kernel's NFC netlink interface and offers them on the system bus
;;; (org.neard), which pro1x-nfc, the NFC wallet, uses.  nfctool, built
;;; with it, lists the adapter and a tag's UID, which neard does not show.
;;; Guix has no neard.  Started at boot by pro1x-nfc-service-type
;;; (services/hardware.scm).
;;;
;;; Two changes from upstream's defaults:
;;; - main.conf (upstream installs none): the adapter powered, ConstantPoll
;;;   off.  Polling all the time would keep the radio busy and cost
;;;   battery; pro1x-nfc starts the poll loop when it scans.
;;; - D-Bus policy: the users group may talk to neard, not only root and
;;;   at_console sessions (Shepherd sets no at_console).
;;;
;;; State: build-tested only.

(define-module (fxtec-pro1x packages nfc)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages linux)       ; libnl
  #:use-module (gnu packages pkg-config)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages))

(define-public neard
  (package
    (name "neard")
    (version "0.20")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://git.kernel.org/pub/scm/network/nfc/neard.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0viiwk1gap3jwf433wnxk5bvg279fzcaalhhp6cqys5flifs6bag"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:configure-flags #~(list "--disable-systemd" "--enable-tools")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'allow-users
            (lambda _
              (substitute* "src/org.neard.conf"
                (("    <policy at_console=\"true\">")
                 "    <policy group=\"users\">
        <allow send_destination=\"org.neard\"/>
    </policy>
    <policy at_console=\"true\">"))))
          ;; Upstream installs no main.conf (its defaults: neither powered
          ;; nor polling); the adapter is to be powered for pro1x-nfc's
          ;; poll loop.
          (add-after 'install 'install-config
            (lambda _
              (let ((dir (string-append #$output "/etc/neard")))
                (mkdir-p dir)
                (call-with-output-file (string-append dir "/main.conf")
                  (lambda (port)
                    (display "[General]
ConstantPoll = false
DefaultPowered = true
ResetOnError = true
" port)))))))))
    (native-inputs (list autoconf autoconf-archive automake libtool pkg-config))
    (inputs (list dbus glib libnl))
    (home-page "https://github.com/linux-nfc/neard")
    (synopsis "Near Field Communication daemon")
    (description
     "neard manages NFC adapters through the Linux kernel's NFC subsystem:
it reads and writes NFC tags (NDEF) and offers adapters, tags and records on
D-Bus.  nfctool lists adapters and tags and sniffs NFC traffic.")
    (license license:gpl2)))
