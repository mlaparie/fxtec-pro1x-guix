#!/usr/bin/env bash
# rag-notes/query.sh — search the rag-notes corpus
#
# Usage:
#   rag-notes/query.sh <regex>            entries whose text matches (case-insensitive)
#   rag-notes/query.sh -c <confidence>    entries with that confidence label
#   rag-notes/query.sh -s <section>       entries in that section
#   rag-notes/query.sh -t ...             titles only
#
# Needs jq (guix shell jq).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
mode=text
titles=false

while getopts "c:s:th" opt; do
    case "$opt" in
        c) mode=confidence; arg="$OPTARG" ;;
        s) mode=section;    arg="$OPTARG" ;;
        t) titles=true ;;
        h|*) sed -n '2,10p' "$0"; exit 0 ;;
    esac
done
shift $((OPTIND - 1))
if [[ "$mode" == text ]]; then
    [[ $# -ge 1 ]] || { sed -n '2,10p' "$0"; exit 1; }
    arg="$1"
fi

for f in "$DIR"/*.json; do
    jq -r --arg mode "$mode" --arg arg "$arg" --argjson titles "$titles" \
       --arg file "$(basename "$f")" '
      to_entries[0].value
      | to_entries[]
      | select(.value | type == "array")
      | .key as $section
      | .value[]
      | select(
          if   $mode == "confidence" then .confidence == $arg
          elif $mode == "section"    then $section == $arg
          else (tostring | test($arg; "i")) end)
      | if $titles then "\($file)/\($section): [\(.confidence)] \(.title)"
        else {file: $file, section: $section} + . end
    ' "$f"
done
