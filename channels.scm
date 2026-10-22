;;; channels.scm — use with `guix pull -C channels.scm` or `guix system -C channels.scm`
;;;
;;; Pulls this channel alongside Guix proper.  The nonguix channel provides the
;;; un-deblobbed `linux` package that linux-pro1x is built on top of.

(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master"))

 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d796ab"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))

 (channel
  (name 'fxtec-pro1x)
  (url "file:///home/mat/Projects/fxtec-pro1x-guix")
  (branch "guix")))
