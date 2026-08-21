#!/usr/bin/env bash
# unicode-guard.sh — added lines of the diff must not carry invisible or
# direction-overriding code points ("Trojan Source", CVE-2021-42574): text a
# reviewer sees rendered one way and the compiler reads another. No test and
# no LLM review sees this class — the bytes are invisible in both.
#
# Flagged (the set is deliberately small so real text never trips it):
#   bidi overrides/embeddings/isolates  U+202A–U+202E, U+2066–U+2069
#   zero-width space / word joiner      U+200B, U+2060
#   zero-width no-break space           U+FEFF — except a BOM as the first
#                                       character of a file's first line
#   Unicode tag characters              U+E0000–U+E007F (ASCII smuggling)
# NOT flagged, on purpose: ZWJ/ZWNJ (U+200C/U+200D — emoji sequences,
# Arabic/Persian typography), LRM/RLM (U+200E/U+200F), soft hyphen (U+00AD).
# Not detected at all: homoglyphs / mixed-script identifiers (`раssword` in
# Cyrillic) — that residue belongs to the LLM security review, which reads the
# identifiers; a byte scanner cannot tell those apart from legitimate text.
# Known false positive: subdivision flag emoji (🏴 + a tag sequence) — spell
# those as text in code, or exclude the path.
#
# One legitimate line (a test fixture for exactly this class, a localisation
# file that must carry an explicit RLE) can carry `unicode-guard:allow` in the
# same line; it is reported on stderr and not counted. Prefer that to widening
# UNICODE_GUARD_EXCLUDE — the allow is visible in the diff, an env var is not.
# Both are escape hatches, not protection: a NEW allow token or exclude entry
# in a change is exactly what the code review must stop at.
#
# Config (env):
#   GATE_BASE_REF           base ref to diff against (overrides auto-detect)
#   STAGED=1                evaluate the staged index instead of a commit range
#   UNICODE_GUARD_EXCLUDE   ERE over paths to skip (vendored fonts, i18n
#                           fixtures); EMPTY (the default) excludes nothing.
#                           Anchor it (`^vendor/`): the excluded path is chosen
#                           by whoever writes the change.
#
# Usage:
#   ci/unicode-guard.sh            # CI: auto-detect base ref
#   ci/unicode-guard.sh --staged   # local / pre-commit: check staged changes
#
# Exit codes: 0 ok · 1 forbidden code point in an added line · 2 config/infra
# (fails closed).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
STAGED="${STAGED:-0}"
[ "${1:-}" = "--staged" ] && STAGED=1
export UNICODE_GUARD_EXCLUDE="${UNICODE_GUARD_EXCLUDE:-}"
echo "unicode-guard: staged=$STAGED exclude=\"${UNICODE_GUARD_EXCLUDE}\"${GATE_BASE_REF:+ base=$GATE_BASE_REF}"

# Byte patterns for the code points above (UTF-8), matched by awk under
# LC_ALL=C so every awk (gawk, mawk, busybox) sees bytes, not characters.
# grep is NOT used for the match: GNU grep in the C locale silently fails to
# match bracket ranges of bytes >= 0x80 (rc 1 — a clean verdict it never
# established); awk handles them identically on the three implementations we
# test. A fourth awk that does not is caught by the self-probe below.
BIDI_RE=$(printf '\xe2\x80[\xaa-\xae]|\xe2\x81[\xa6-\xa9]')
ZW_RE=$(printf '\xe2\x80\x8b|\xe2\x81\xa0')
BOM_RE=$(printf '\xef\xbb\xbf')
TAG_RE=$(printf '\xf3\xa0[\x80\x81][\x80-\xbf]')
# Control bytes that mark content as binary-ish (NUL cannot live in a shell
# variable, so it is checked separately in awk). Used only to annotate a
# finding, never to skip content.
BIN_RE=$(printf '[\x01-\x08\x0b\x0c\x0e-\x1f]')
export BIDI_RE ZW_RE BOM_RE TAG_RE BIN_RE

# --- self-probe: prove THIS awk matches these byte ranges before trusting a
# clean verdict from it. A "no findings" from an awk that cannot see the bytes
# is indistinguishable from a clean diff — the exact fail-open this layer is
# supposed to close.
probe=$(printf 'clean line\nbidi \xe2\x80\xae here\nzw \xe2\x80\x8b here\ntag \xf3\xa0\x81\x81 here\nbom \xef\xbb\xbf here\n' \
  | LC_ALL=C awk '
      $0 ~ ENVIRON["BIDI_RE"] { n++ }
      $0 ~ ENVIRON["ZW_RE"]   { n++ }
      $0 ~ ENVIRON["TAG_RE"]  { n++ }
      $0 ~ ENVIRON["BOM_RE"]  { n++ }
      /^clean line$/          { c++ }
      END { printf "%d %d", n + 0, c + 0 }') || {
  echo "unicode-guard: awk failed on the self-probe. Failing closed." >&2; exit 2; }
[ "$probe" = "4 1" ] || {
  echo "unicode-guard: this awk cannot match the byte patterns (probe='$probe', expected '4 1') — a clean verdict from it would be meaningless. Install gawk/mawk/busybox awk. Failing closed." >&2
  exit 2; }

# --- the diff (added lines only: -U0, no context).
# Every knob that could empty this input is pinned, because each one is
# reachable from inside the change under review or from the developer's own
# config: `-diff` in .gitattributes (or a NUL byte) would print "Binary files
# differ" instead of the lines — `--text` overrides both; `diff.external` /
# textconv would replace the diff entirely; `color.ui=always` would wrap the
# lines in escape codes; `diff.noprefix` / `diff.mnemonicPrefix` would change
# `+++ b/path` into something the parser reads as a different path.
tmp=$(mktemp) || { echo "unicode-guard: cannot create a temp file. Failing closed." >&2; exit 2; }
trap 'rm -f "$tmp"' EXIT
GIT_DIFF=(git -c core.quotePath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false
          diff -U0 --no-color --no-ext-diff --no-textconv --text --no-renames)
if [ "$STAGED" = "1" ]; then
  if ! "${GIT_DIFF[@]}" --cached > "$tmp"; then
    echo "unicode-guard: git diff --cached failed. Failing closed." >&2; exit 2
  fi
else
  BASE=$(GATE_LAYER=unicode-guard bash "$here/base-ref.sh") || exit $?
  if ! "${GIT_DIFF[@]}" "${BASE}...HEAD" > "$tmp"; then
    echo "unicode-guard: git diff failed. Failing closed." >&2; exit 2
  fi
fi

# Walk the unified diff: track the current file and the new-side line number,
# test every added line. Findings → stdout as path:line: <what>; exit 1.
LC_ALL=C awk '
  function report(what) { printf "%s:%d: %s\n", file, ln, what; found = 1 }
  /^diff --git / { file = ""; inhunk = 0; first = 0; next }
  /^\+\+\+ /     { file = substr($0, 5); if (file ~ /^b\//) file = substr(file, 3)
                   inhunk = 0; first = 1
                   skip = (ENVIRON["UNICODE_GUARD_EXCLUDE"] != "" && file ~ ENVIRON["UNICODE_GUARD_EXCLUDE"])
                   next }
  /^@@ /         { if ($0 !~ /^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/) {
                     printf "unicode-guard: unparseable hunk header for %s: %s\n", file, $0 > "/dev/stderr"; broken = 1; exit 2 }
                   match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; inhunk = 1; next }
  !inhunk        { next }
  /^\\/          { next }                       # "\ No newline at end of file"
  /^-/           { next }
  /^\+/ {
    line = substr($0, 2)
    if (skip) { ln++; next }
    # Binary-looking content is scanned like everything else: skipping it would
    # hand anyone a one-byte switch (a NUL or a form feed in the same file)
    # for turning this layer off. A real binary asset that trips the patterns
    # is a false positive with a visible fix — exclude that path. (busybox awk
    # truncates a record at the first NUL, so on that awk the bytes after a NUL
    # are not scanned: less, never more.)
    isbin = (line ~ ENVIRON["BIN_RE"] || index(line, sprintf("%c", 0)) > 0)
    if (index(line, "unicode-guard:allow") > 0) {
      printf "unicode-guard: allowed inline: %s:%d\n", file, ln > "/dev/stderr"
      ln++; first = 0; next
    }
    hint = isbin ? " [line looks binary — if this is a real binary asset, exclude the path]" : ""
    if (line ~ ENVIRON["BIDI_RE"]) report("bidi override/isolate (U+202A-202E, U+2066-2069)" hint)
    if (line ~ ENVIRON["ZW_RE"])   report("zero-width space / word joiner (U+200B, U+2060)" hint)
    if (line ~ ENVIRON["TAG_RE"])  report("Unicode tag character (U+E0000-E007F)" hint)
    bom = line
    if (first && ln == 1 && index(bom, ENVIRON["BOM_RE"]) == 1) bom = substr(bom, 4)   # a leading BOM on line 1 is a BOM
    if (bom ~ ENVIRON["BOM_RE"])   report("zero-width no-break space (U+FEFF) inside a line" hint)
    ln++; first = 0; next
  }
  END { if (broken) exit 2; exit found ? 1 : 0 }
' "$tmp" && rc=0 || rc=$?
case "$rc" in
  0) echo "unicode-guard: OK" ;;
  1) echo "unicode-guard: FAILED — invisible or direction-overriding code points in added lines (see above)" >&2 ;;
  *) echo "unicode-guard: cannot evaluate the diff (awk failed, rc=$rc). Failing closed." >&2; exit 2 ;;
esac
exit "$rc"
