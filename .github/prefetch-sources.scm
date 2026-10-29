;;; .github/prefetch-sources.scm — list GitHub tarball sources of this channel
;;;
;;; Prints "URL FILE-NAME" for each package in modules/fxtec-pro1x/packages whose
;;; source is a url-fetch from github.com.  CI downloads these with retries
;;; and adds them to the store, because the daemon's own anonymous download
;;; gets HTTP 429 from codeload.github.com on runners and no Guix mirror
;;; carries these tarballs.  Same file name and hash, so the store path is
;;; the one the package expects.
;;;
;;; Usage: guix repl -L modules .github/prefetch-sources.scm          list
;;;        guix repl -L modules .github/prefetch-sources.scm FILE...  add to store
;;;
;;; add-to-store sends the file's contents over the daemon socket, so the
;;; daemon never needs to see the file itself.

(use-modules (guix packages)
             (guix discovery)
             (guix store)
             (gnu packages)
             (srfi srfi-1))

(define files (cdr (command-line)))

(unless (null? files)
  (with-store store
    (for-each (lambda (file)
                (display (add-to-store store (basename file) #f "sha256"
                                       file))
                (newline))
              files))
  (exit 0))

(define modules
  (all-modules `((,(string-append (getcwd) "/modules") . "fxtec-pro1x/packages"))))

(define (github-source package)
  (let ((source (package-source package)))
    (and (origin? source)
         (string? (origin-uri source))
         (string-contains (origin-uri source) "github.com")
         (cons (origin-uri source)
               (or (origin-file-name source)
                   (basename (origin-uri source)))))))

(for-each (lambda (pair)
            (format #t "~a ~a~%" (car pair) (cdr pair)))
          (delete-duplicates
           (filter-map github-source (fold-packages cons '() modules))))
