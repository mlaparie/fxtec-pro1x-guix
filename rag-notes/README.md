# rag-notes

Findings from porting Guix System to the F(x)tec Pro1X (SM6115), kept as
structured JSON so a coding agent can look them up instead of guessing. Every entry
says how it is known and where it came from.

There is no retrieval engine. The corpus is small enough that an agent reads the
chapter it needs, or queries it with `jq` (see below). The format follows
moWerk's [sailfish-rag](https://github.com/moWerk/sailfish-rag) `Mainline/` corpus,
so entries can be compared, and sent there as an issue if they correct it.

## Chapters

| file | holds |
|---|---|
| `hardware.json` | what holds on this phone under any OS: boot chain, kernel, display and touch, firmware, modem, FDE, USB networking. Only what this port measured or had to solve; everything else is in sailfish-rag `Mainline/` |
| `guix.json` | what is specific to Guix: Shepherd services, packaging, the build sandbox, CI, deployment, licensing |
| `nixos_to_guix.json` | each module of the NixOS port, the Guix code that translates it, its state, and what changed or got lost in the translation |

Keep the three apart. A hardware lesson must stay true if the OS changes; a Guix
lesson must stay true if the phone changes.

## Reference corpora (read-only, not copied here)

- **sailfish-rag `Mainline/`** (moWerk, GPL-3.0-or-later): about 270 hardware findings
  for this exact phone and SoC, mostly confirmed on a 7.3 kernel under SailfishOS.
  Clone it to `/tmp/sailfish-rag` and read the chapter for the subsystem in front of
  you (`audio.json`, `modem.json`, `camera.json`, `sensors.json`, ...) before
  working on it. Not useful here: `packaging.json`, `userspace_sailfishos.json`,
  `SailfishOS/`. `devices.json` is SailfishOS's feature state, not ours.
- **The NixOS port** (nyymi609/fxtec-pro1x-nixos): the working hardware reference.
  Clone it to `/tmp/fxtec-pro1x-nixos`.

When an entry here relies on one of them, it says so with confidence `reported`
and names the source.

## Entry format

Each chapter file is one object: `{ "<chapter>": { "note": "...", "<section>": [ entries ] } }`.

Every entry has these six fields:

| field | content |
|---|---|
| `title` | the finding in one line |
| `general` | the lesson for any port of this kind |
| `instance` | this device, kernel, Guix commit, file, numbers |
| `confidence` | one of the labels below |
| `date` | when it was observed (ISO date) |
| `source` | commit hash, file and line, log, or URL |

`nixos_to_guix.json` entries add `nixos` (module path), `guix` (file or files) and
`status` (`working`, `partial`, `untested`, `missing`).

## Confidence labels

Strongest first.

- `confirmed`: observed on the device, or read in the source, by the session that
  wrote the entry. Say which in `source`.
- `handover`: taken from a commit message, `TODO.md` or another session's summary
  and not re-checked. Most entries seeded from the git history start here.
  Re-check one before building on it, then raise it to `confirmed`.
- `reported`: someone else said it, and they are named (sailfish-rag, NixOS port,
  a mailing list post).
- `vendor_doc` / `community_doc`: read from documentation, with the URL and date.
- `inferred`: reasoned, not observed. Weakest; say what would confirm it.

When a newer observation contradicts an entry, correct the entry, keep the old
claim in `instance` as "previously: ...", and give the date of the correction.
Dead ends stay in, because they save the next session time.

## Querying

```sh
rag-notes/query.sh modem           # every entry whose text matches "modem"
rag-notes/query.sh -c handover     # every entry with that confidence
rag-notes/query.sh -s ci           # every entry in section "ci"
```

`query.sh` needs `jq` (`guix shell jq`).

## What never goes in

No passwords, IMEI, IMSI, ICCID, MAC addresses, SSIDs, serial numbers, phone
numbers, or names that embed them (ModemManager and NetworkManager connection
names can contain the operator or SSID). Write "home Wi-Fi", "the SIM", "the unit".
`scripts/check-private.sh` refuses commits that look like they contain them;
install it as a pre-commit hook (see the script header).

## Writing entries

- Add entries while working, not at the end of a session.
- One finding per entry. Link related entries by title in `instance` if needed.
- Commit hashes in `source` are from this repository unless another is named.
- Validate before committing: `jq empty rag-notes/*.json`.
