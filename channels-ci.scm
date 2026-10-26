;;; channels-ci.scm — pinned guix+nonguix for GitHub Actions builds
;;;
;;; Does NOT include fxtec-pro1x — the CI workflow uses -L . instead
;;; so it always builds the current checkout, not a pinned commit.
;;;
;;; Update commits with: git ls-remote <url> refs/heads/master
;;;
(list
 (channel
  (name 'guix)
  (url "https://codeberg.org/guix/guix.git")
  (branch "master")
  (commit "ad54bd54243362b138ecc33c7b87695d0bb7b0d4")
  (introduction
   (make-channel-introduction
    "c91e27c60864faa229198f6f0caf620275c429a2"
    (openpgp-fingerprint
     "510A 8628 E2A7 7678 8F8C  709C 4BC0 2592 5FF8 F4D3"))))

 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master")
  (commit "c241d19ff840dc75556f722b231760d119b6adea")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d796ab"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29 12AF 6F51 20A0 22FB B2D5")))))
