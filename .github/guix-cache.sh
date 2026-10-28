#!/usr/bin/env bash
# .github/guix-cache.sh — carry CI's own Guix builds over to the next run
#
#   bash .github/guix-cache.sh export DIR   after the build (also on failure)
#   bash .github/guix-cache.sh import DIR   before the build
#
# A fresh runner has an empty Guix database, so caching /gnu/store as plain
# files is useless: the daemon treats unregistered items as invalid.  This
# exports what the job built itself (outputs of every derivation with a build
# log in /var/log/guix/drvs; substituted items have none) with their closures,
# as a signed archive, and imports it on the next run.  Only the public half
# of the exporting run's signing key is cached; the importing run authorizes
# it.  Disk images and partitions are skipped: they change on every commit.

set -euo pipefail

cmd=$1
dir=$2

case $cmd in
  export)
    rm -rf "$dir"
    mkdir -p "$dir"
    [ -f /etc/guix/signing-key.sec ] || sudo guix archive --generate-key
    : > "$dir/items.txt"
    # Logs under 8 KiB come from trivial builders (config files, profiles).
    sudo find /var/log/guix/drvs -name '*.drv.gz' -size +8k | while read -r log; do
      rel=${log#/var/log/guix/drvs/}
      drv=/gnu/store/${rel%%/*}${rel#*/}
      drv=${drv%.gz}
      case $drv in
        *disk-image*|*partition.img*|*genimage*) continue ;;
      esac
      [ -f "$drv" ] || continue
      { grep -o '("[a-z0-9_-]*","/gnu/store/[^"]*"' "$drv" || true; } \
        | sed 's/.*,"//; s/"$//' \
        | while read -r out; do
            if [ -e "$out" ]; then echo "$out"; fi
          done
    done | sort -u > "$dir/items.txt"
    echo "==> $(wc -l < "$dir/items.txt") built items to cache"
    if [ -s "$dir/items.txt" ]; then
      # shellcheck disable=SC2046
      sudo guix archive --export -r $(cat "$dir/items.txt") \
        | zstd -T0 -3 -q > "$dir/items.nar.zst"
      sudo cat /etc/guix/signing-key.pub > "$dir/signing-key.pub"
    fi
    du -sh "$dir"
    ;;
  import)
    if [ ! -f "$dir/items.nar.zst" ]; then
      echo "==> no Guix build cache"
      exit 0
    fi
    du -sh "$dir"
    sudo guix archive --authorize < "$dir/signing-key.pub"
    zstd -dc "$dir/items.nar.zst" | sudo guix archive --import \
      || echo "WARNING: importing the Guix build cache failed; building without it"
    rm -f "$dir/items.nar.zst"
    ;;
  *)
    echo "usage: $0 export|import DIR" >&2
    exit 2
    ;;
esac
