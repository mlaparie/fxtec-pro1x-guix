;;; channels-lock.scm — pinned channel commits for reproducible builds
;;;
;;; Use with:
;;;   guix pull -C channels-lock.scm
;;;   guix system -C channels-lock.scm reconfigure systems/mobile.scm
;;;
;;; guix and nonguix: the commits release 0.1.2 was built and tested with
;;; (same as channels-ci.scm).  fxtec-pro1x: the release tag.
;;;
;;; Regenerate with:
;;;   guix describe --format=channels > channels-lock.scm
;;;   (keep only guix, nonguix, and fxtec-pro1x entries)

(list
 (channel
  (name 'guix)
  (url "https://codeberg.org/guix/guix.git")
  (branch "master")
  (commit "8b96d76752be5bfe4ce87e32a53afa919d365fd0")
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
     "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))

 (channel
  (name 'fxtec-pro1x)
  (url "https://git.sr.ht/~mlaparie/fxtec-pro1x-guix")
  (branch "main")
  (commit "v0.1.2")))  ; a tag: Guix resolves commit as tag-or-commit
