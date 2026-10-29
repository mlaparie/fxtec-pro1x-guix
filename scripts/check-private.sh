#!/usr/bin/env bash
# scripts/check-private.sh — refuse commits that look like they leak device identity
#
# Checks the lines a commit adds for IMEI/ICCID/IMSI-like digit runs, MAC
# addresses, phone numbers, and the literal strings listed one per line in
# .git/info/private-patterns (never committed: put your SSIDs, hostnames,
# phone number, etc. there).
#
# Install as a pre-commit hook:
#   ln -s ../../scripts/check-private.sh .git/hooks/pre-commit
#
# Run by hand on the staged changes:   scripts/check-private.sh
# Run on a commit range before a push: scripts/check-private.sh origin/main..HEAD

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ $# -ge 1 ]]; then
    added=$(git diff "$1" | grep '^+' | grep -v '^+++' || true)
else
    added=$(git diff --cached | grep '^+' | grep -v '^+++' || true)
fi
[[ -n "$added" ]] || exit 0

fail=0
check() {   # description, extended regex
    local hits
    hits=$(grep -nE -- "$2" <<<"$added" || true)
    if [[ -n "$hits" ]]; then
        echo "check-private: possible $1:" >&2
        echo "$hits" | head -5 >&2
        fail=1
    fi
}

# 15 digits (IMEI, IMSI), 19-20 digits (ICCID), not part of a longer hex string.
check "IMEI/IMSI/ICCID" '(^|[^0-9a-fA-F])([0-9]{15}|[0-9]{19,20})([^0-9a-fA-F]|$)'
# MAC addresses.
check "MAC address" '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'
# International phone numbers.
check "phone number" '\+[1-9][0-9 ]{8,15}[0-9]'

patterns=.git/info/private-patterns
if [[ -f "$patterns" ]]; then
    while IFS= read -r p; do
        [[ -z "$p" || "$p" == \#* ]] && continue
        if grep -qiF -- "$p" <<<"$added"; then
            echo "check-private: a string from $patterns appears in the changes" >&2
            fail=1
        fi
    done < "$patterns"
fi

if [[ $fail -ne 0 ]]; then
    echo "check-private: commit refused. Remove the values, or bypass once with git commit --no-verify if they are false positives." >&2
    exit 1
fi
