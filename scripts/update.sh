#!/usr/bin/env bash
# scripts/update.sh — deploy a new Guix generation over USB ethernet
#
# Usage:
#   bash scripts/update.sh systems/minimal.scm
#   bash scripts/update.sh systems/mobile.scm [user@host]
#
# The phone must be reachable at 172.16.42.1 (USB gadget Ethernet).
# The Guix store closure is copied over SSH then activated.

set -euo pipefail

SYSTEM="${1:-systems/minimal.scm}"
TARGET="${2:-user@172.16.42.1}"
ARCH="aarch64-linux"

die() { echo "error: $*" >&2; exit 1; }

echo "==> Building $SYSTEM for $ARCH …"
RESULT=$(guix system build \
    --system="$ARCH" \
    -L . \
    "$SYSTEM" 2>&1 | tail -1)
echo "    $RESULT"

echo "==> Copying store closure to $TARGET …"
guix copy --to="ssh://$TARGET" "$RESULT"

echo "==> Activating on device …"
# shellcheck disable=SC2029
ssh "$TARGET" "sudo guix system reconfigure /run/current-system --no-bootloader && \
               sudo /run/current-system/bin/switch-to-system"

echo ""
echo "Done.  Reboot the device to load the new generation:"
echo "  ssh $TARGET 'sudo reboot'"
