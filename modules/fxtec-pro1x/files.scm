;;; fxtec-pro1x/files.scm — absolute paths to the repository's data files
;;;
;;; Patches, configs and firmware data live outside modules/ (device/,
;;; packages/).  A literal relative local-file is resolved against the
;;; module's own directory only when Guix knows where the module came
;;; from; when it looks a package up by name (guix build phosh-pro1x) it
;;; is resolved against the current directory and fails.  So find this
;;; file on the load path, resolve symlinks (a pulled channel's modules
;;; are reached through profile links) and go up to the repository.

(define-module (fxtec-pro1x files)
  #:export (%fxtec-pro1x-root
            repository-file))

(define %fxtec-pro1x-root
  ;; modules/fxtec-pro1x/files.scm -> the repository root.
  (let ((this (search-path %load-path "fxtec-pro1x/files.scm")))
    (dirname (dirname (dirname (canonicalize-path this))))))

(define (repository-file name)
  "Return the absolute file name of NAME, relative to the repository root,
e.g. \"device/kernel/config.aarch64\"."
  (string-append %fxtec-pro1x-root "/" name))
