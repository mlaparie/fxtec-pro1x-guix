;;; fxtec-pro1x/packages/bootloader.scm — extlinux bootloader for U-Boot
;;;
;;; The upstream extlinux-bootloader depends on syslinux, which uses
;;; -mregparm=3 in its BIOS build — a flag removed in GCC 14.  On this device
;;; U-Boot reads extlinux.conf natively; we don't need syslinux installed on
;;; disk at all.  This module provides:
;;;
;;;   syslinux-stub        — a trivial package with the directory layout that
;;;                          extlinux-bootloader expects, plus a no-op extlinux
;;;                          binary so the install step silently succeeds.
;;;   pro1x-extlinux-bootloader — extlinux-bootloader with syslinux-stub as its
;;;                          package; otherwise identical.

(define-module (fxtec-pro1x packages bootloader)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:export (pro1x-extlinux-bootloader))

(define syslinux-stub
  (package
    (name "syslinux")
    (version "stub")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list #:builder
           #~(begin
               (mkdir #$output)
               (mkdir (string-append #$output "/share"))
               (mkdir (string-append #$output "/share/syslinux"))
               (mkdir (string-append #$output "/bin"))
               ;; No-op extlinux binary: U-Boot reads extlinux.conf itself.
               (let ((bin (string-append #$output "/bin/extlinux")))
                 (call-with-output-file bin
                   (lambda (p) (display "#!/bin/sh\nexit 0\n" p)))
                 (chmod bin #o755)))))
    (home-page "https://wiki.syslinux.org/")
    (synopsis "Syslinux stub (U-Boot reads extlinux.conf natively)")
    (description "Stub package: no x86 BIOS build, just the directory layout
that extlinux-bootloader expects.  U-Boot on the Pro1X reads extlinux.conf
directly, so the syslinux MBR installer is never invoked.")
    (license license:gpl2+)))

(define-public pro1x-extlinux-bootloader
  (bootloader
   (inherit extlinux-bootloader)
   (package syslinux-stub)))
