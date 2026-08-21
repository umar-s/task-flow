#!/usr/bin/env bash
# readme-parity.sh — README.ru.md is a full translation of README.md, not a
# summary (CLAUDE.md → Conventions). Text differs by language; structure must
# not: heading levels in order, fenced code blocks, table row counts, badges.
# Lines inside a fenced code block are opaque (a `# comment` there is not a heading).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

shape() {
  awk '
    function flush() { if (t) { print "TABLE " t; t = 0 } }
    /^```/     { flush(); if (in_code) { in_code = 0 } else { in_code = 1; print "CODE" }; next }
    in_code    { next }
    /^#{1,6} / { flush(); match($0, /^#+/); print "H" RLENGTH; next }
    /^\|/      { t++; next }
               { flush() }
    END        { flush() }
  ' "$1"
}
badges() { grep -c '^\[!\[' "$1" || true; }   # a zero count is a value, not an error

d=$(diff <(shape README.md) <(shape README.ru.md) || true)
b1=$(badges README.md); b2=$(badges README.ru.md)
if [ -n "$d" ] || [ "$b1" != "$b2" ]; then
  echo "readme-parity: README.md and README.ru.md differ in structure (left = en, right = ru):" >&2
  [ -n "$d" ] && printf '%s\n' "$d" >&2
  [ "$b1" != "$b2" ] && echo "badge lines: $b1 vs $b2" >&2
  exit 1
fi
echo "readme-parity: OK"
