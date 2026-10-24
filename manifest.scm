;;; manifest.scm — flash tooling for the build/flash machine
;;;
;;; Use with:
;;;   guix shell -m manifest.scm -- bash scripts/flash.sh systems/phosh.scm
;;;
;;; Provides: fastboot, mkbootimg, partx (util-linux), e2label (e2fsprogs)

(use-modules (guix profiles))

(specifications->manifest
 '("fastboot"
   "mkbootimg"
   "util-linux"
   "e2fsprogs"))
