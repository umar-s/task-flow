#!/usr/bin/env bash
# tests/gitleaks-fetch.sh — negative controls for templates/ci-gate/ci/gitleaks-fetch.sh.
# Needs network once (the first download); everything after runs on the cache.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FETCH="$ROOT/templates/ci-gate/ci/gitleaks-fetch.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GITLEAKS_CACHE_DIR="$TMP/cache" GITLEAKS_RUN_DIR="$TMP/run"
pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }
runs() { find "$GITLEAKS_RUN_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
TARBALL=$(sed -nE 's/^PIN_VERSION="([0-9.]+)"/gitleaks_\1_linux_x64.tar.gz/p' "$FETCH")

# a) fresh: downloads, verifies, caches, extracts into a private dir, binary runs
B1=$(bash "$FETCH" 2>"$TMP/err") && [ -x "$B1" ] && "$B1" version >/dev/null && [ -f "$GITLEAKS_CACHE_DIR/$TARBALL" ] && ok || bad "fresh fetch: $(cat "$TMP/err")"
# b) cached: a private copy is verified, a NEW private dir is used
B2=$(bash "$FETCH" 2>"$TMP/err") && [ "$B1" != "$B2" ] && grep -q 'cached tarball verified' "$TMP/err" && ok || bad "cached fetch: $(cat "$TMP/err")"
[ "$(runs)" = 2 ] && ok || bad "expected 2 run dirs, found $(runs)"
# c) tampered cache: discarded and re-downloaded, binary still runs
printf 'x' >> "$GITLEAKS_CACHE_DIR/$TARBALL"
B3=$(bash "$FETCH" 2>"$TMP/err") && grep -q 'discarding' "$TMP/err" && "$B3" version >/dev/null && ok || bad "tampered cache: $(cat "$TMP/err")"
# d) tampered cache + no network: non-zero, empty stdout, no run dir or cache entry left behind
printf 'x' >> "$GITLEAKS_CACHE_DIR/$TARBALL"
n=$(runs)
curl() { return 22; }; wget() { return 1; }; export -f curl wget
out=$(bash "$FETCH" 2>/dev/null) && rc=0 || rc=$?
unset -f curl wget
[ "$rc" != 0 ] && [ -z "$out" ] && [ "$(runs)" = "$n" ] && [ ! -f "$GITLEAKS_CACHE_DIR/$TARBALL" ] && ok || bad "no-network: rc=$rc out='$out' runs=$(runs)"
# e) wrong committed checksum: exit 1, nothing cached, nothing left behind
sed 's/^SHA256_x64=.*/SHA256_x64="0000000000000000000000000000000000000000000000000000000000000000"/' "$FETCH" > "$TMP/fetch-bad.sh"
n=$(runs)
out=$(bash "$TMP/fetch-bad.sh" 2>"$TMP/err") && rc=0 || rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && grep -q 'CHECKSUM MISMATCH' "$TMP/err" && [ "$(runs)" = "$n" ] && [ ! -f "$GITLEAKS_CACHE_DIR/$TARBALL" ] && ok || bad "bad checksum: rc=$rc $(cat "$TMP/err")"
# f) cache is an optimisation: unreadable cached tarball → re-download, not a crash
# g) read-only cache dir after a successful verification: still succeeds (just not cached)
# Both need permission bits to bite — as root they don't, so the branch would never be entered.
if [ "$(id -u)" = 0 ]; then
  echo "tests/gitleaks-fetch: running as root — (f)/(g) permission fixtures skipped" >&2
  B4=$(bash "$FETCH" 2>"$TMP/err") && ok || bad "fetch as root: $(cat "$TMP/err")"; B5=$B4
else
  bash "$FETCH" >/dev/null 2>&1; chmod 000 "$GITLEAKS_CACHE_DIR/$TARBALL"
  B4=$(bash "$FETCH" 2>"$TMP/err") && "$B4" version >/dev/null && grep -q 'unreadable' "$TMP/err" && ok || bad "unreadable cache: $(cat "$TMP/err")"
  chmod 644 "$GITLEAKS_CACHE_DIR/$TARBALL"
  rm -rf "$GITLEAKS_CACHE_DIR"; mkdir -p "$GITLEAKS_CACHE_DIR"; chmod 555 "$GITLEAKS_CACHE_DIR"
  B5=$(bash "$FETCH" 2>"$TMP/err") && "$B5" version >/dev/null && grep -q 'not cached' "$TMP/err" && ok || bad "read-only cache: $(cat "$TMP/err")"
  chmod 755 "$GITLEAKS_CACHE_DIR"
fi
# h) stdout carries only the path (every run)
for b in "$B1" "$B2" "$B3" "$B4" "$B5"; do case "$b" in */gitleaks) ;; *) bad "stdout not a bare path: '$b'";; esac; done; ok

echo "tests/gitleaks-fetch: $pass passed, $fail failed"
[ "$fail" = 0 ]
