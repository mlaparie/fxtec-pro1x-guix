;;; fxtec-pro1x/packages/waydroid-bt.scm — Bluetooth LE and GPS for Waydroid
;;;
;;; Waydroid's images strip Android's Bluetooth app and ship no Bluetooth
;;; HAL, so Android apps see no Bluetooth; and no GNSS HAL, so only network
;;; location.  waydroid-host-stack (isyourbrainfoss, MIT) bridges both from
;;; the host without handing the radio to Android: in Android, a soft HCI
;;; HAL speaks to a socket; on the host, waydroid-bt-host answers it through
;;; BlueZ, which keeps the adapter (Bluetooth LE GATT only: phone keys,
;;; sensors; no audio).  Its GPS side gives Android the host's GeoClue
;;; position through Android's test providers.
;;;
;;;   waydroid-host-stack   the host programs, built here from its sources
;;;   waydroid-bt-overlay   the files for Waydroid's overlay (see below)
;;;
;;; services/waydroid.scm installs and runs them (bluetooth? in
;;; waydroid-configuration).
;;;
;;; State: Bluetooth on in Android with the phone's adapter, and the Tesla
;;; app seeing it (author, 2026-11-18, set up by hand); these packages and
;;; the service build-tested only.

(define-module (fxtec-pro1x packages waydroid-bt)
  #:use-module (fxtec-pro1x files)
  #:use-module (gnu packages base)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages glib)          ; dbus
  #:use-module (gnu packages linux)         ; e2fsprogs
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages protobuf)
  #:use-module (guix build-system cargo)
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:))

(define waydroid-host-stack-commit "d9a316e97e720dfdb112b17643ba2d4d117a91c1")

(define waydroid-host-stack-source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://github.com/isyourbrainfoss/waydroid-host-stack")
          (commit waydroid-host-stack-commit)))
    (file-name (git-file-name "waydroid-host-stack"
                              (string-take waydroid-host-stack-commit 7)))
    (sha256
     (base32 "0iwav9yfvmwwnsg6kxyh2q25wx0jiq7fxabj695wbfa882ps6jzf"))))

(define-public waydroid-host-stack
  (package
    (name "waydroid-host-stack")
    (version (git-version "0.1.0" "0" waydroid-host-stack-commit))
    ;; An LE link shared by several guest clients is dropped only when the
    ;; last one goes (the Tesla phone key's link went 2 s after a reuse).
    (source
     (origin
       (inherit waydroid-host-stack-source)
       (patches
        (list
         (local-file
          (repository-file "device/patches/waydroid-host-stack-shared-link-owners.patch")
          "waydroid-host-stack-shared-link-owners.patch")))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f
      ;; The bridge, its ping, the JNI patcher and the GeoClue reader.
      #:cargo-install-paths ''("host")
      ;; Its tests start a BlueZ client.
      #:tests? #f))
    (native-inputs (list pkg-config protobuf))
    (inputs (cons dbus
                  (cargo-inputs 'waydroid-host-stack
                                #:module '(fxtec-pro1x packages waydroid-bt-crates))))
    (home-page "https://github.com/isyourbrainfoss/waydroid-host-stack")
    (synopsis "Bluetooth LE and GPS from the host for Waydroid")
    (description
     "waydroid-bt-host answers Waydroid's soft HCI HAL through BlueZ, so that
Android apps use the host's Bluetooth LE adapter while BlueZ keeps it.
waydroid-geoclue-fix reads the host's position from GeoClue for Android's
test providers.  waydroid-bt-jni-patch adapts Android 13's Bluetooth JNI
library to a container without CAP_WAKE_ALARM.")
    (license license:expat)))

;; LineageOS 20's Bluetooth app and JNI library, the same build as Waydroid's
;; image (TQ3A.230901.001): Waydroid's own builds strip the app.  From
;; AndyYan's LineageOS 20 GSI (arm64, vanilla), its btservices APEX.
(define lineageos-20-gsi
  (origin
    (method url-fetch)
    (uri (string-append "mirror://sourceforge/andyyan-gsi/lineage-20-td/"
                        "lineage-20.0-20251021-UNOFFICIAL-arm64_bvN.img.gz"))
    (sha256
     (base32 "024lb592ihpdh53a8m8lg5z98mv200rkq1n66lff50zy7qwr4avv"))))

;; The files of Waydroid's overlay, under system/ and vendor/ as there:
;; the Bluetooth app in its APEX (an app outside it cannot find its JNI
;; library), the JNI library patched by waydroid-bt-jni-patch (Android's
;; timers with CLOCK_BOOTTIME instead of CLOCK_BOOTTIME_ALARM, which a
;; container without CAP_WAKE_ALARM is refused), the app's privileged
;; permissions and Bluetooth features, and the soft HCI HAL with its init
;; script and VINTF manifest.  Only for Waydroid's LineageOS 20 image.
(define-public waydroid-bt-overlay
  (package
    (name "waydroid-bt-overlay")
    (version "20-TQ3A.230901.001")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((sys (string-append #$output "/system"))
                 (apex (string-append sys "/apex/com.android.btservices"))
                 (app (string-append apex "/app/Bluetooth@TQ3A.230901.001"))
                 (hal (string-append #$waydroid-host-stack-source "/guest/hal"))
                 (dev #$(local-file (repository-file "device/waydroid/bluetooth")
                                    "waydroid-bt-files" #:recursive? #t)))
            (setenv "PATH" (string-append #$gzip "/bin:" #$e2fsprogs "/sbin:"
                                          #$unzip "/bin:" #$coreutils "/bin"))
            (define (dump image from to)
              (invoke "debugfs" "-R" (string-append "dump " from " " to) image)
              (unless (file-exists? to)
                (error "not in the image:" from)))
            (with-directory-excursion (mkdtemp "/tmp/gsi-XXXXXX")
              (system (string-append "gunzip -c " #$lineageos-20-gsi " > gsi.img"))
              (dump "gsi.img" "/system/apex/com.android.btservices.apex" "bt.apex")
              (delete-file "gsi.img")
              (invoke "unzip" "-q" "bt.apex" "apex_payload.img")
              (mkdir-p app)
              (mkdir-p (string-append apex "/lib64"))
              (dump "apex_payload.img" "/app/Bluetooth@TQ3A.230901.001/Bluetooth.apk"
                    (string-append app "/Bluetooth.apk"))
              (dump "apex_payload.img" "/lib64/libbluetooth_jni.so" "jni.so")
              (invoke #$(file-append waydroid-host-stack "/bin/waydroid-bt-jni-patch")
                      "jni.so" (string-append apex "/lib64/libbluetooth_jni.so")))
            (for-each (lambda (f)
                        (install-file (string-append dev "/" f)
                                      (string-append sys "/etc/permissions")))
                      '("privapp-permissions-com.android.bluetooth.xml"
                        "android.hardware.bluetooth.xml"))
            (install-file (string-append dev "/android.hardware.bluetooth@1.0-service.waydroid")
                          (string-append sys "/bin/hw"))
            (copy-file (string-append hal "/bluetooth-hci-waydroid.sh")
                       (string-append sys "/bin/bluetooth-hci-waydroid"))
            (install-file (string-append hal "/android.hardware.bluetooth@1.0-service.waydroid.rc")
                          (string-append sys "/etc/init"))
            (mkdir-p (string-append #$output "/vendor/etc/vintf/manifest"))
            (copy-file (string-append hal "/manifest_android.hardware.bluetooth@1.0.xml")
                       (string-append #$output "/vendor/etc/vintf/manifest/"
                                      "android.hardware.bluetooth@1.0-service.waydroid.xml"))
            (for-each (lambda (f) (chmod f #o755))
                      (list (string-append sys "/bin/bluetooth-hci-waydroid")
                            (string-append sys "/bin/hw/android.hardware.bluetooth@1.0-service.waydroid")))))))
    (home-page "https://github.com/isyourbrainfoss/waydroid-host-stack")
    (synopsis "Android's Bluetooth back in Waydroid's LineageOS 20 image")
    (description
     "The files that Waydroid's overlay needs for Bluetooth LE in Android:
LineageOS 20's Bluetooth app and patched JNI library, and waydroid-host-stack's
soft HCI HAL, which talks to waydroid-bt-host on the host.")
    ;; The app and library: Apache 2.0 (AOSP, LineageOS); the HAL: MIT.
    (license (list license:asl2.0 license:expat))))
