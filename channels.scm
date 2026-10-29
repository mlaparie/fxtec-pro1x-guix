;;; channels.scm — the channels a Pro¹x system follows: the phone ships this
;;; same file as /etc/guix/channels.scm (generated from
;;; modules/fxtec-pro1x/services/channels.scm; keep the two equal).  Use it
;;; with `guix pull -C channels.scm`, or copy it to
;;; ~/.config/guix/channels.scm to add your own channels.
;;;
;;; guix and nonguix are pinned to the commits the port is built and tested
;;; with.  No substitute server builds this port's packages yet: with other
;;; guix or nonguix commits, `guix pull' followed by a reconfigure would
;;; make the phone build the kernel, Phosh and much of their dependencies
;;; itself, which takes hours.  The pins move with the port's releases; if
;;; you remove them, expect long builds on the phone.

(list (channel
       (name 'guix)
       (url "https://git.guix.gnu.org/guix.git")
       (branch "master")
       (commit "8b96d76752be5bfe4ce87e32a53afa919d365fd0")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      (channel
       (name 'nonguix)
       (url "https://gitlab.com/nonguix/nonguix")
       (branch "master")
       (commit "c241d19ff840dc75556f722b231760d119b6adea")
       (introduction
        (make-channel-introduction
         "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
         (openpgp-fingerprint
          "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
      (channel
       (name 'fxtec-pro1x)
       (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
       (branch "main")))
