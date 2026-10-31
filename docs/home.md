# Home files (Guix Home)

Files in your home directory come in three kinds:

| kind | what Guix does | edit where |
|---|---|---|
| managed | symlinks it from the store, replaces it on every deploy | `config.scm` (or a file next to it) |
| seeded | copies it once, if missing; never touches it again | on the phone, in place |
| unmanaged | nothing | on the phone |

Use *managed* for files you want reproducible, *seeded* for defaults you
will keep editing on the phone.  The port's Sway, bar and foot settings
need neither: they follow deploys, and your `~/.config` files only add to
them ([configure.md](configure.md#files-outside-configscm)).

## Setting it up

In `~/.config/guix/config.scm`, add to the services:

```scheme
(use-modules (gnu services guix)              ; guix-home-service-type
             (fxtec-pro1x home)               ; pro1x-home
             (fxtec-pro1x packages misc))     ; pro1x-sway-config

(service guix-home-service-type
         `(("user"
            ,(pro1x-home
              #:managed `((".config/foot/foot.ini"
                           ,(local-file "foot.ini")))
              #:seeded `((".config/sway/config"
                          ,(file-append pro1x-sway-config
                                        "/share/pro1x-sway/config")))))))
```

Paths are relative to the home directory.  `local-file` paths are relative
to `config.scm`; keep those files next to it.  `#:packages` adds packages to
the user's home profile; `#:services` takes any Guix Home service.

Deploy as usual (`scripts/deploy.sh`): the home environment is part of the
system and is activated at boot and on each deploy.

## What happens to existing files

- Managed: Guix Home moves a file it would replace to
  `~/TIMESTAMP-guix-home-legacy-configs-backup/` first.
- Seeded: an existing file (or link) is left alone.  To get the default
  again, delete the file and deploy.

## State

Seeded and managed files tested in `guix home container` (2026-10-30);
not yet deployed to the phone.
