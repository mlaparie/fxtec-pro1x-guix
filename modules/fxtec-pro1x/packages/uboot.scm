;;; fxtec-pro1x/packages/uboot.scm — U-Boot 2026.10-rc for the SM6115 Pro1X
;;;
;;; Mirrors the NixOS packages/uboot/default.nix:
;;;   • replaces UEFI boot with sysboot/extlinux
;;;   • inserts N "Boot previous generation" menu entries
;;;   • patches USB gadget (high-speed, UTMI pipe clock) and UFS GDSC
;;;
;;; `previous-generations` (default 3) must match what systems/minimal.scm
;;; requests; it is compiled into U-Boot so reflash after changing it.

(define-module (fxtec-pro1x packages uboot)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bison)
  #:use-module (gnu packages bootloaders)
  #:use-module (gnu packages cross-base)
  #:use-module (gnu packages compiler-tools)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages python)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages vim)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (make-u-boot-pro1x
            u-boot-pro1x))

;; (cross-gcc "aarch64-linux-gnu") fails to build from source in the Guix
;; sandbox because the stmp-fixinc Makefile target exits 1 when
;; BUILD_SYSTEM_HEADER_DIR (/usr/include) doesn't exist (non-FHS sandbox).
;;
;; The phase-based fix (substitute-keyword-arguments on #:phases) silently
;; fails for cross-gcc because the phases gexp isn't substitutable that way.
;; Instead, patch gcc/Makefile.in in the source origin snippet so the fix
;; applies to both the full and sans-libc cross-gcc variants (they share the
;; same source origin).
;;
;; The snippet must also reproduce the original cross-gcc-snippet substitution
;; (the TOOLDIR_BASE_PREFIX fix) because we replace the snippet field entirely.
(define cross-gcc-aarch64
  (let ((base (cross-gcc "aarch64-linux-gnu")))
    (package
      (inherit base)
      (source
       (origin
         (inherit (package-source base))
         (snippet
          '(begin
             ;; Reproduced from cross-gcc-snippet: fix TOOLDIR_BASE_PREFIX so
             ;; GCC finds its shared libraries in the separate "lib" output.
             (substitute* "gcc/Makefile.in"
               (("-DTOOLDIR_BASE_PREFIX=[^ ]*")
                "-DTOOLDIR_BASE_PREFIX=\\\"../../../../\\\""))
             ;; stmp-fixinc exits 1 when /usr/include is absent (Guix sandbox).
             ;; Change to `true` so the step continues with an empty
             ;; include-fixed/ instead of aborting.
             (substitute* "gcc/Makefile.in"
               (("then sleep 1; else exit 1; fi")
                "then sleep 1; else true; fi"))
             #t)))))))

(define (native-aarch64?)
  (string-prefix? "aarch64" (%current-system)))

(define* (make-u-boot-pro1x #:key (previous-generations 3))
  (let* ((n previous-generations)
         ;; "bootmenu_1=Boot previous generation 1=sysboot …\n" × n
         (prev-entries
          (apply string-append
                 (map (lambda (i)
                        (string-append
                         "bootmenu_" (number->string i)
                         "=Boot previous generation " (number->string i)
                         "=sysboot scsi 0#userdata any ${scriptaddr}"
                         " /boot/extlinux/prev" (number->string i)
                         ".conf; pause\n"))
                      (iota n 1)))))
    (package
      (name "u-boot-pro1x")
      (version "2026.10-rc-f8eb346")
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/u-boot/u-boot")
               (commit "f8eb3469e1a17c79b047b3fd38ae820e8816a115")))
         (file-name (git-file-name name version))
         (sha256
          (base32 "0vfryrywjwxvd1iddyx6hzc3c7mxxvci44853wrpnff1c0sx64jk"))))
      (build-system gnu-build-system)
      ;; On an aarch64 build machine (CI) the native compiler builds
      ;; U-Boot: a same-triplet cross-gcc bootstraps itself and fails
      ;; ("Link tests are not allowed after GCC_NO_EXECUTABLES",
      ;; stage2-libiberty, run 40988527489).
      (native-inputs
       (append
        (list bison flex gnutls openssl perl python-minimal-wrapper xxd)
        (if (native-aarch64?)
            '()
            (list cross-gcc-aarch64
                  (cross-binutils "aarch64-linux-gnu")))))
      (arguments
       (list
        #:make-flags
        #~(list "ARCH=arm"
                #$(if (native-aarch64?)
                      "CROSS_COMPILE="
                      "CROSS_COMPILE=aarch64-linux-gnu-")
                "DEVICE_TREE=qcom/sm6115-fxtec-pro1x"
                "HOSTCC=gcc")
        #:tests? #f
        #:phases
        #~(modify-phases %standard-phases
            (replace 'configure
              (lambda* (#:key make-flags #:allow-other-keys)
                ;; Mirror NixOS buildUBoot defconfig = "qcom_defconfig qcom-phone.config":
                ;; 1. apply base defconfig
                ;; 2. make qcom-phone.config — this runs merge_config.sh -m (finds
                ;;    board/qualcomm/qcom-phone.config, overrides conflicts including
                ;;    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE) then `make oldconfig`
                ;; 3. append extra options + olddefconfig (mirrors NixOS extraConfig)
                (apply invoke "make" "qcom_defconfig" make-flags)
                (apply invoke "make" "qcom-phone.config" make-flags)
                ;; Enable sysboot + extras (matches NixOS extraConfig).
                (invoke "sh" "-c"
                        "printf 'CONFIG_CMD_SYSBOOT=y\\nCONFIG_CMD_HASH=y\\n' >> .config")
                (apply invoke "make" "olddefconfig" make-flags)))

            (add-after 'configure 'patch-boot-env
              (lambda _
                ;; Patch qcom-phone.env to use sysboot (mirrors NixOS exactly).
                ;; Do NOT patch default.env — qcom-phone.env IS the DEFAULT_ENV_FILE
                ;; for phones (CONFIG_PHONE_QCOM) and overrides bootcmd there.
                (substitute* "board/qualcomm/qcom-phone.env"
                  (("bootcmd=bootefi bootmgr; pause; run menucmd")
                   "bootcmd=sysboot scsi 0#userdata any ${scriptaddr} /boot/extlinux/extlinux.conf; pause; run menucmd")
                  (("bootmenu_0=Boot=bootefi bootmgr; pause")
                   "bootmenu_0=Boot=sysboot scsi 0#userdata any ${scriptaddr} /boot/extlinux/extlinux.conf; pause"))

                ;; 2. Renumber existing entries ≥ 1 to make room for prev-N slots.
                #$@(if (> n 0)
                       (list #~(begin
                                 (invoke "perl" "-0pi" "-e"
                                         (string-append
                                          "s/^bootmenu_(\\d+)=/"
                                          "'bootmenu_'.($1>=1?$1+" #$(number->string n) ":$1).'='/gme")
                                         "board/qualcomm/qcom-phone.env")
                                 ;; Insert the prev entries before the (now-renumbered) slot 1+n.
                                 (call-with-output-file "prev-entries.txt"
                                   (lambda (port) (display #$prev-entries port)))
                                 (invoke "perl" "-0pi" "-e"
                                         (string-append
                                          "BEGIN{local $/;open F,'<prev-entries.txt' or die;$e=<F>;}"
                                          "s/^(bootmenu_" #$(number->string (+ n 1)) "=)/$e$1/m or die")
                                         "board/qualcomm/qcom-phone.env")))
                       '())

                ;; 3. USB gadget: high-speed only + UTMI pipe clock.
                (let ((dts "dts/upstream/src/arm64/qcom/sm6115-fxtec-pro1x.dts"))
                  (let ((port (open-file dts "a")))
                    (display "\n&usb_dwc3 {\n\
\t/delete-property/ usb-role-switch;\n\
\tmaximum-speed = \"high-speed\";\n\
\tdr_mode = \"peripheral\";\n\
\tphys = <&usb_hsphy>;\n\
\tphy-names = \"usb2-phy\";\n\
};\n\
&usb { qcom,select-utmi-as-pipe-clk; };\n"
                            port)
                    (close-port port)))

                ;; 4. UFS GDSC entry in the SM6115 clock driver.
                (substitute* "drivers/clk/qcom/clock-sm6115.c"
                  (("\t\\[GCC_USB30_PRIM_GDSC\\] = \\{ 0x1a004 \\},")
                   "\t[GCC_UFS_PHY_GDSC] = { 0x45004 },\n\t[GCC_USB30_PRIM_GDSC] = { 0x1a004 },"))))

            (replace 'build
              (lambda* (#:key make-flags parallel-build? #:allow-other-keys)
                (apply invoke "make"
                       (string-append "-j" (if parallel-build?
                                               (number->string (parallel-job-count))
                                               "1"))
                       make-flags)))

            (replace 'install
              (lambda* (#:key outputs #:allow-other-keys)
                (let ((out (assoc-ref outputs "out")))
                  ;; u-boot-nodtb.bin: U-Boot without appended DTB, used by
                  ;; flash.sh which appends the DTB explicitly (gz-dtb format).
                  ;; Using u-boot.bin would embed the DTB twice.
                  (install-file "u-boot-nodtb.bin"
                                (string-append out "/libexec"))
                  (install-file
                   "dts/upstream/src/arm64/qcom/sm6115-fxtec-pro1x.dtb"
                   (string-append out "/libexec"))))))))
      (home-page "https://www.denx.de/wiki/U-Boot")
      (synopsis "U-Boot for the F(x)tec Pro1X (SM6115)")
      (description
       "U-Boot 2026.10-rc configured for the Qualcomm SM6115 Pro1X.
Boots via sysboot/extlinux from the userdata partition; the U-Boot menu
(hold volume-down at power on) offers N slots for previous Guix generations.")
      (license license:gpl2+))))

(define-public u-boot-pro1x
  (make-u-boot-pro1x))
