#!/usr/bin/env bash
# diff-coverage.sh — changed-line coverage threshold, tool-agnostic.
#
# Global coverage % is vanity: it moves too slowly to notice an untested change.
# This gate looks only at the lines this change added or modified, and fails
# when too few of them are executed by a test.
#
# It reads a coverage report the project's own test run produced — lcov,
# Cobertura XML, or Clover XML — so it stays language-agnostic (jest/vitest,
# pytest-cov, PHPUnit, JaCoCo→cobertura, go tool cover→cobertura, …).
#
# Config (env):
#   GATE_COVERAGE_REPORT  path(s) to the report, space-separated. UNSET → the
#                         layer is skipped (same convention as MIGRATION_DIRS).
#   GATE_COVERAGE_MIN     minimum % of changed, instrumented lines (default 80)
#   GATE_BASE_REF         base ref to diff against (overrides auto-detect)
#   GATE_COVERAGE_MISSES  how many uncovered lines to list per file (default 10)
#   GATE_COVERAGE_STRICT  1 → a change with zero measurable lines fails instead
#                         of passing. Turn this on once the report path is
#                         proven (see the negative control in the ci-gate
#                         skill): it is what stops a stale or wrong report from
#                         reading like a clean diff.
#
# Usage:
#   ci/diff-coverage.sh
#
# Exit codes: 0 ok · 1 below threshold · 2 config/infra (fails closed).
set -euo pipefail

# Verdicts are byte comparisons, so the locale must not decide them: in tr_TR
# and az_AZ, `i` and `I` are not a case pair, and `grep -i` there stops
# matching lowercase `index`, `constraint`, `trigger`, `materialized`.
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)

REPORTS="${GATE_COVERAGE_REPORT:-}"
MIN="${GATE_COVERAGE_MIN:-80}"
MAX_MISSES="${GATE_COVERAGE_MISSES:-10}"

if [ -z "$REPORTS" ]; then
  echo "diff-coverage: GATE_COVERAGE_REPORT not set, skipping"
  exit 0
fi

case "$MIN" in
  ''|*[!0-9]*) echo "diff-coverage: GATE_COVERAGE_MIN='$MIN' is not an integer. Failing closed." >&2; exit 2 ;;
esac

# --- base ref: one resolution for every range-based layer (ci/base-ref.sh)
BASE=$(GATE_LAYER=diff-coverage bash "$here/base-ref.sh") || exit $?

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. normalise every report to "path|line|hits" ---------------------------
: > "$tmp/cov"
for report in $REPORTS; do
  if [ ! -s "$report" ]; then
    echo "diff-coverage: report '$report' is missing or empty. Failing closed." >&2
    exit 2
  fi

  if grep -q '^SF:' "$report"; then
    fmt=lcov
  elif grep -q 'hits=' "$report"; then
    fmt=cobertura
  elif grep -q 'count=' "$report"; then
    fmt=clover
  else
    echo "diff-coverage: '$report' is not lcov, Cobertura or Clover (no SF:/hits=/count=). Failing closed." >&2
    exit 2
  fi
  echo "diff-coverage: reading $report ($fmt)"

  # `tr '>' '\n'` puts every XML element on its own record, so a minified
  # report parses the same as a pretty-printed one.
  tr '>' '\n' < "$report" | awk -v fmt="$fmt" '
    function attr(s, name,   p, rest, q) {
      p = index(s, name "=\"")
      if (p == 0) return ""
      rest = substr(s, p + length(name) + 2)
      q = index(rest, "\"")
      if (q == 0) return ""
      return substr(rest, 1, q - 1)
    }
    fmt == "lcov" {
      if (substr($0, 1, 3) == "SF:") { f = substr($0, 4); next }
      if (substr($0, 1, 3) == "DA:") {
        split(substr($0, 4), a, ",")
        if (f != "" && a[1] != "") print f "|" a[1] "|" (a[2] + 0)
      }
      next
    }
    fmt == "cobertura" {
      if (index($0, "<class ") && index($0, "filename=\"")) { f = attr($0, "filename"); next }
      if (index($0, "<line ") && index($0, "number=\"")) {
        n = attr($0, "number"); h = attr($0, "hits")
        if (f != "" && n != "" && h != "") print f "|" n "|" (h + 0)
      }
      next
    }
    fmt == "clover" {
      if (index($0, "<file ") && index($0, "name=\"")) { f = attr($0, "name"); next }
      if (index($0, "<line ") && index($0, "num=\"")) {
        n = attr($0, "num"); h = attr($0, "count")
        if (f != "" && n != "" && h != "") print f "|" n "|" (h + 0)
      }
      next
    }
  ' >> "$tmp/cov"
done

if [ ! -s "$tmp/cov" ]; then
  echo "diff-coverage: parsed 0 lines out of the report(s) — stale, truncated or an unexpected dialect. Failing closed." >&2
  exit 2
fi

# --- 2. changed (added/modified) lines of the new revision -------------------
git -c core.quotePath=false diff -U0 --no-color "${BASE}...HEAD" \
  | awk '
      function cnt(spec,   n, a) { n = split(spec, a, ","); return (n > 1) ? a[2] + 0 : 1 }
      # A header is only a header outside a hunk: an added line whose content
      # starts with "++ " arrives as "+++ …" and would otherwise re-point the
      # current file, dropping the rest of the diff out of the denominator.
      !inhunk && /^\+\+\+ / {
        p = substr($0, 5)
        if (p == "/dev/null") { f = "" } else { sub(/^b\//, "", p); f = p }
        next
      }
      !inhunk && /^@@ / {
        minus = $2; sub(/^-/, "", minus)
        plus = $3; sub(/^\+/, "", plus)      # "+c,d" (or "+c")
        pending = cnt(minus) + cnt(plus); inhunk = (pending > 0)
        if (f == "") next
        n = split(plus, a, ",")
        start = a[1] + 0
        count = (n > 1) ? a[2] + 0 : 1
        for (i = 0; i < count; i++) print f "|" (start + i)
        next
      }
      inhunk && /^\\/ { next }                  # "\ No newline at end of file"
      inhunk && /^[+-]/ { pending--; if (pending <= 0) inhunk = 0; next }
    ' > "$tmp/changed"

if [ ! -s "$tmp/changed" ]; then
  echo "diff-coverage: no added or modified lines in ${BASE}...HEAD — nothing to measure"
  exit 0
fi

# --- 3. intersect, report, decide -------------------------------------------
# A report path matches a changed path when one is a path-suffix of the other
# (reports carry absolute or build-root-relative paths; git does not).
awk -v min="$MIN" -v max_misses="$MAX_MISSES" -v strict="${GATE_COVERAGE_STRICT:-0}" '
  function norm(p) { sub(/^\.\//, "", p); return p }
  function matches(rp, cp) {
    if (rp == cp) return 1
    if (length(rp) > length(cp) && substr(rp, length(rp) - length(cp)) == "/" cp) return 1
    if (length(cp) > length(rp) && substr(cp, length(cp) - length(rp)) == "/" rp) return 1
    return 0
  }
  NR == FNR {
    split($0, t, "|")
    p = norm(t[1])
    hits[p "|" t[2]] = t[3] + 0
    if (!(p in seen_path)) { seen_path[p] = 1; paths[++np] = p }
    next
  }
  {
    split($0, c, "|")
    cp = norm(c[1]); cl = c[2]
    rp = ""
    if (cp in resolved) { rp = resolved[cp] }
    else {
      for (i = 1; i <= np; i++) if (matches(paths[i], cp)) { rp = paths[i]; break }
      resolved[cp] = rp
    }
    if (rp == "") next                       # file not instrumented — not measurable
    k = rp "|" cl
    if (!(k in hits)) next                   # line not coverable (blank, comment, decl)
    total++
    if (hits[k] > 0) covered++
    else {
      missed[cp] = missed[cp] " " cl
      nmiss[cp]++
    }
  }
  END {
    if (total == 0) {
      print "diff-coverage: 0 instrumented changed lines (docs/config only, or the report does not cover the changed files)"
      if (strict) {
        fflush()
        print "diff-coverage: STRICT — a change with nothing measurable is treated as unproven" > "/dev/stderr"
        exit 1
      }
      exit 0
    }
    pct = covered * 100 / total
    for (f in missed) {
      n = split(missed[f], L, " ")
      out = ""
      shown = 0
      for (i = 1; i <= n; i++) {
        if (L[i] == "") continue
        if (shown >= max_misses) { out = out " …+" (nmiss[f] - shown) " more"; break }
        out = out " " L[i]; shown++
      }
      printf "  uncovered %s:%s\n", f, out
    }
    printf "diff-coverage: %d/%d changed lines covered (%.1f%%), threshold %d%%\n", covered, total, pct, min
    if (pct + 0.0001 < min) {
      fflush()
      print "diff-coverage: FAILED" > "/dev/stderr"
      exit 1
    }
    print "diff-coverage: OK"
    exit 0
  }
' "$tmp/cov" "$tmp/changed"
