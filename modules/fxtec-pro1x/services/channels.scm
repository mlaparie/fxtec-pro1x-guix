;;; fxtec-pro1x/services/channels.scm — the channels a Pro1X system uses
;;;
;;; %pro1x-channels: guix, nonguix and this channel, on their main branches.
;;; The systems install it as /etc/guix/channels.scm (guix-configuration
;;; channels), so `guix pull' on the phone follows these three; users add
;;; more in ~/.config/guix/channels.scm.  deploy/pro1x.scm records the same
;;; three as the provenance of deployed generations.
;;;
;;; State: /etc/guix/channels.scm not yet pulled from on the phone.

(define-module (fxtec-pro1x services channels)
  #:use-module (guix channels)
  #:export (%nonguix-channel
            %fxtec-pro1x-channel
            %pro1x-channels))

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

;; Commits are not signed, so there is no channel introduction.
(define %fxtec-pro1x-channel
  (channel
   (name 'fxtec-pro1x)
   (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
   (branch "main")))

(define %pro1x-channels
  (append %default-channels             ;guix
          (list %nonguix-channel %fxtec-pro1x-channel)))
