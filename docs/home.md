# Home files (Guix Home)

Files in your home directory come in three kinds:

| kind | what Guix does | edit where |
|---|---|---|
| managed | symlinks it from the store, replaces it on every deploy | `home.scm` (or a file next to it) |
| seeded | copies it once, if missing; never touches it again | on the phone, in place |
| unmanaged | nothing | on the phone |

Use *managed* for files you want reproducible, *seeded* for defaults you
will keep editing on the phone.  The port's Sway, bar and foot settings
need neither: they follow deploys, and your `~/.config` files only add to
them ([configure.md](configure.md#files-outside-configscm)).

## Setting it up

Your Guix Home lives in `~/.config/guix/home.scm`, next to `config.scm`,
which includes it; the system builds and activates it on every deploy or
reconfigure.  `/etc/guix/home.scm` is a starting file:

```sh
cp /etc/guix/home.scm ~/.config/guix/
```

In `~/.config/guix/home.scm`, your packages and home files:

```scheme
(define home
  (pro1x-home
   #:packages (specifications->packages (list "htop" "mosh"))
   #:managed `((".config/foot/foot.ini" ,(local-file "foot.ini")))
   #:seeded `((".config/sway/config"
               ,(file-append pro1x-sway-config
                             "/share/pro1x-sway/config")))))
```

In `~/.config/guix/config.scm`, include it and add the service:

```scheme
(use-modules (gnu services guix)              ; guix-home-service-type
             (fxtec-pro1x home)               ; pro1x-home
             (fxtec-pro1x packages misc))     ; pro1x-sway-config

(include "home.scm")

;; in the operating-system's services:
(service guix-home-service-type `(("user" ,home)))
```

Paths are relative to the home directory.  `local-file` paths are relative
to `config.scm`; keep those files next to it (`scripts/deploy.sh` copies
the whole `~/.config/guix`, but `current`).  `#:packages` adds packages to
your home profile: put them here rather than through `guix install`, so a
reflash keeps them.  `#:services` takes any Guix Home service.

Deploy as usual (`scripts/deploy.sh`).  Do not run `guix home reconfigure`
on top: it would make a second home generation, beside the system's.
`~/guix-home-config.scm`, which Guix puts in new homes, is for that
standalone use and is not read here.

## What happens to existing files

- Managed: Guix Home moves a file it would replace to
  `~/TIMESTAMP-guix-home-legacy-configs-backup/` first.
- Seeded: an existing file (or link) is left alone.  To get the default
  again, delete the file and deploy.

## State

Seeded and managed files tested in `guix home container` (2026-10-30);
not yet deployed to the phone.
