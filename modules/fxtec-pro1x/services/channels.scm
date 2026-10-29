;;; fxtec-pro1x/services/channels.scm — the channels a Pro¹x system follows
;;;
;;; %pro1x-channels: guix and nonguix pinned to the commits this port is
;;; built and tested with, and this channel on its main branch.  The phone
;;; gets them as /etc/guix/channels.scm (pro1x-channels-file, installed by
;;; (fxtec-pro1x system common)), with a header saying why the pins are
;;; there: nothing builds this channel's packages for a substitute server
;;; yet, so with other guix or nonguix commits the phone would rebuild the
;;; kernel, Phosh and their dependencies itself, for hours.  deploy/pro1x.scm
;;; records the same three as the provenance of deployed generations.
;;;
;;; Keep %pro1x-guix-commit and %pro1x-nonguix-commit equal to the commits
;;; in channels-lock.scm and channels-ci.scm.
;;;
;;; State: pulled from on the phone 2026-10-29 (via channels-lock.scm).

(define-module (fxtec-pro1x services channels)
  #:use-module (guix channels)
  #:use-module (guix gexp)
  #:use-module (ice-9 pretty-print)
  #:export (%pro1x-guix-commit
            %pro1x-nonguix-commit
            %nonguix-channel
            %fxtec-pro1x-channel
            %pro1x-channels
            pro1x-channels-file))

(define %pro1x-guix-commit "8b96d76752be5bfe4ce87e32a53afa919d365fd0")
(define %pro1x-nonguix-commit "c241d19ff840dc75556f722b231760d119b6adea")

(define %nonguix-channel
  (channel
   (name 'nonguix)
   (url "https://gitlab.com/nonguix/nonguix")
   (branch "master")
   (introduction
    (make-channel-introduction
     "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
     (openpgp-fingerprint
      "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5")))))

;; Commits are not signed yet, so there is no channel introduction.
(define %fxtec-pro1x-channel
  (channel
   (name 'fxtec-pro1x)
   (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
   (branch "main")))

(define %pro1x-channels
  (list (channel
         (inherit (car %default-channels)) ;guix, with its introduction
         (commit %pro1x-guix-commit))
        (channel
         (inherit %nonguix-channel)
         (commit %pro1x-nonguix-commit))
        %fxtec-pro1x-channel))

(define pro1x-channels-file
  (plain-file
   "channels.scm"
   (string-append
    ";;; /etc/guix/channels.scm — the channels this phone follows, written by
;;; the fxtec-pro1x channel.  Copy it to ~/.config/guix/channels.scm to add
;;; your own channels.
;;;
;;; guix and nonguix are pinned to the commits the port is built and tested
;;; with.  No substitute server builds this port's packages yet: with other
;;; guix or nonguix commits, `guix pull' followed by a reconfigure would
;;; make the phone build the kernel, Phosh and much of their dependencies
;;; itself, which takes hours.  The pins move with the port's releases; if
;;; you remove them, expect long builds on the phone.

"
    (call-with-output-string
      (lambda (port)
        (pretty-print `(list ,@(map channel->code %pro1x-channels))
                      port))))))
