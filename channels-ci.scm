;;; channels-ci.scm — pinned guix+nonguix for GitHub Actions builds
;;;
;;; Does NOT include fxtec-pro1x — the CI workflow uses -L . instead
;;; so it always builds the current checkout, not a pinned commit.
;;;
;;; guix is pinned for reproducibility.  nonguix is NOT pinned because
;;; the upstream repo has had force-pushes; a stale commit pin causes
;;; guix pull / time-machine to silently drop the channel.

(list
 (channel
  (name 'guix)
  (url "https://codeberg.org/guix/guix.git")
  (branch "master")
  (commit "ab5a40491d1b551b73060cd82d25aa3fd0c04773")
  (introduction
   (make-channel-introduction
    "c91e27c60864faa229198f6f0caf620275c429a2"
    (openpgp-fingerprint
     "510A 8628 E2A7 7678 8F8C  709C 4BC0 2592 5FF8 F4D3"))))

 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d796ab"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29 12AF 6F51 20A0 22FB B2D5")))))
