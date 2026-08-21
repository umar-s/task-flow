#!/usr/bin/env bash
# readme-parity.sh — README.ru.md is a full translation of README.md, not a
# summary (CLAUDE.md → Conventions). Text differs by language; structure must
# not: heading levels in order, fenced code blocks, table row counts, badges.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

shape() {
  awk '
    /^#{1,6} / { if (t) { print "TABLE " t; t = 0 }; match($0, /^#+/); print "H" RLENGTH; next }
    /^```/     { if (t) { print "TABLE " t; t = 0 }; print "CODE"; next }
    /^\|/      { t++; next }
               { if (t) { print "TABLE " t; t = 0 } }
    END        { if (t) print "TABLE " t }
  ' "$1"
}
badges() { grep -c '^\[!\[' "$1" || true; }   # lint: allow — a zero count is a value, not an error

d=$(diff <(shape README.md) <(shape README.ru.md) || true)
b1=$(badges README.md); b2=$(badges README.ru.md)
if [ -n "$d" ] || [ "$b1" != "$b2" ]; then
  echo "readme-parity: README.md and README.ru.md differ in structure (left = en, right = ru):" >&2
  [ -n "$d" ] && printf '%s\n' "$d" >&2
  [ "$b1" != "$b2" ] && echo "badge lines: $b1 vs $b2" >&2
  exit 1
fi
echo "readme-parity: OK"
