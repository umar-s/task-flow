#!/usr/bin/env bash
# tests/diff-coverage.sh — negative controls for templates/ci-gate/ci/diff-coverage.sh.
#
# The layer judges a coverage report against the lines a change added. Both
# directions matter: a change whose new lines are untested must fail, and a
# change whose new lines are covered must pass — plus every way the layer could
# report "fine" without having measured anything (unset report, unreadable
# report, wrong dialect, a diff it mis-parsed).
# Exit codes: 0 ok · 1 below threshold · 2 config/infra (fails closed).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/templates/ci-gate/ci"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
R="$TMP/repo"
G() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }

git init -q -b main "$R"; mkdir -p "$R/ci"; cp "$SRC"/*.sh "$R/ci/"
printf 'x = 1\n' > "$R/app.py"; G add -A; G commit -qm init
G checkout -q -b feature

check() {  # name expected [must-match]
  local name="$1" expect="$2" want="${3:-}" rc out
  out=$( cd "$R" && env GATE_BASE_REF=main bash ci/diff-coverage.sh 2>&1 ) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ] && { [ -z "$want" ] || printf '%s' "$out" | grep -q -- "$want"; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$out" >&2
  fi
}

# lcov for app.py: line 2 covered, line 3 not
lcov() { printf 'SF:%s\nDA:2,%s\nDA:3,%s\nend_of_record\n' "$1" "$2" "$3" > "$R/cov.info"; }

# a) unset report → the layer skips itself and says so
printf 'y = 2\nz = 3\n' >> "$R/app.py"; G add -A; G commit -qm change
( cd "$R" && GATE_BASE_REF=main bash ci/diff-coverage.sh > "$TMP/out" 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 0 ] && grep -q 'not set, skipping' "$TMP/out" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL unset-report: rc=$rc $(cat "$TMP/out")" >&2; }
export GATE_COVERAGE_REPORT=cov.info

# b) both changed lines covered → pass
lcov app.py 3 1; check all-covered 0 '2/2 changed lines covered'
# c) half covered, threshold 80 → fail
lcov app.py 3 0; check half-covered 1 'FAILED'
# d) same report, threshold 50 → pass
GATE_COVERAGE_MIN=50 check half-covered-lower-threshold 0 '50.0%'
# e) uncovered lines are named
lcov app.py 3 0; ( cd "$R" && GATE_BASE_REF=main bash ci/diff-coverage.sh 2>&1 || true ) | grep -q 'uncovered app.py: 3' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL misses-not-listed" >&2; }
# f) report that covers nothing of the change: 0 measurable → pass, and STRICT → fail
lcov other/file.py 3 1; check nothing-measurable 0 '0 instrumented changed lines'
GATE_COVERAGE_STRICT=1 check nothing-measurable-strict 1 'STRICT'
# g) missing / unreadable / empty / wrong-dialect report → fail closed
rm -f "$R/cov.info"; check missing-report 2
printf '' > "$R/cov.info"; check empty-report 2
printf 'not a coverage report at all\n' > "$R/cov.info"; check garbage-report 2
# h) a non-integer threshold is a config error
lcov app.py 3 1; GATE_COVERAGE_MIN=eighty check bad-threshold 2 'not an integer'
# i) no base ref at all → fail closed (base-ref.sh)
lcov app.py 3 1
out=$( cd "$R" && bash ci/diff-coverage.sh 2>&1 ) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL no-base-ref: rc=%s\n%s\n' "$rc" "$out" >&2; }
# j) an added line that looks like a diff header must not re-point the parser.
#    "++ note" reaches the parser as "+++ note"; read as a header it re-points
#    the current file, and every LATER hunk of that file silently drops out of
#    the denominator — the gate then measures a fraction of the change and
#    calls it covered. Needs two hunks: the lookalike in the first, real new
#    code in the second.
G checkout -q main
{ echo 'a = 0'; for i in $(seq 1 40); do echo "pad$i = $i"; done; } > "$R/big.py"
G add -A; G commit -qm base-big
G checkout -q -b hdr
{ echo 'a = 0'; echo '++ note'; for i in $(seq 1 40); do echo "pad$i = $i"; done; echo 'tail1 = 1'; echo 'tail2 = 2'; } > "$R/big.py"
G add -A; G commit -qm hdr
# lines 43/44 (the second hunk) are instrumented and uncovered; line 2 is not
printf 'SF:big.py\nDA:43,0\nDA:44,0\nend_of_record\n' > "$R/cov.info"
out=$( cd "$R" && GATE_BASE_REF=main bash ci/diff-coverage.sh 2>&1 ) && rc=0 || rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '0/2 changed lines'; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL header-lookalike (later hunks must still count): rc=%s\n%s\n' "$rc" "$out" >&2; fi

echo "tests/diff-coverage: $pass passed, $fail failed"
[ "$fail" = 0 ]
