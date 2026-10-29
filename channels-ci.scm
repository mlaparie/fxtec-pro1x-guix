;;; channels-ci.scm — pinned guix+nonguix for GitHub Actions builds
;;;
;;; Does NOT include fxtec-pro1x — the CI workflow uses -L modules instead
;;; so it always builds the current checkout, not a pinned commit.
;;;
;;; Update commits with: git ls-remote <url> refs/heads/master
;;;
(list
 (channel
  (name 'guix)
  (url "https://codeberg.org/guix/guix.git")
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
     "2A39 3FFF 68F4 EF7A 3D29 12AF 6F51 20A0 22FB B2D5")))))
