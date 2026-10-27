;;; manifest.scm — flash tooling for the build/flash machine
;;;
;;; scripts/flash.sh re-execs itself inside "guix shell -m manifest.scm" automatically.
;;; Provides: fastboot, mkbootimg, partx (util-linux), e2label (e2fsprogs)

(use-modules (guix profiles))

(specifications->manifest
 '("fastboot"
   "mkbootimg"
   "util-linux"    ; partx, dd
   "e2fsprogs"     ; e2label, mke2fs, debugfs
   "cryptsetup"))  ; luksFormat (flash-encrypted.sh only)
