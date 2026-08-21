#!/usr/bin/env bash
# tests/gate-selftest.sh — the selftest must itself be able to fail.
# `gate.sh --selftest` is what a user runs to prove their gate is wired; this
# proves the selftest goes red when the gate is weakened (a guard regex
# emptied, an allowlist that swallows everything) and green on the real payload.
# Needs network once (pinned gitleaks); set GITLEAKS_CACHE_DIR to reuse a cache.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GITLEAKS_CACHE_DIR="${GITLEAKS_CACHE_DIR:-$TMP/cache}" GITLEAKS_RUN_DIR="$TMP/run" GATE_PINNED_ONLY=1
pass=0; fail=0
R="$TMP/repo"
scaffold() { rm -rf "$R"; git init -q "$R"; mkdir -p "$R/ci"; cp "$ROOT"/templates/ci-gate/ci/*.sh "$R/ci/"; cp "$ROOT/templates/ci-gate/.gitleaks.toml" "$R/"; }
check() {  # name expected [must-match]
  local out rc
  out=$(cd "$R" && env "${ENV[@]}" bash ci/gate.sh --selftest 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$out" | grep -q -- "$3"; }; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$1" "$rc" "$2" "$out" >&2; fi
}
ENV=()

# a) the real payload passes its own selftest, and says what that proves
scaffold; mkdir -p "$R/db/migrate"
check real-payload-green 0 'proves wiring, not coverage'
# b) no migrations dir in the repo: still green, but says the guard watches empty dirs
scaffold
check warns-when-no-migration-dir 0 'watching empty dirs'
# c) custom MIGRATION_DIRS: fixtures land under the first one
scaffold; mkdir -p "$R/database/migrations"
ENV=(MIGRATION_DIRS="database/migrations"); check custom-migration-dirs 0 'MIGRATION_DIRS="database/migrations"'; ENV=()
# d) guard regex emptied → red
scaffold; sed -i "s/^SQL_RE=.*/SQL_RE='(NEVERMATCH)'/" "$R/ci/migration-guard.sh"
check weakened-sql-re-red 1 'FAIL  migration-guard: unmarked DROP'
# e) the marker check relaxed back to a bare marker → red
scaffold; sed -i "s/^APPROVAL_RE=.*/APPROVAL_RE='destructive:[[:space:]]*approved'/" "$R/ci/migration-guard.sh"
check bare-marker-accepted-red 1 'marker w/o reason'
# f) allowlist everything → red, with the hint
scaffold; printf '\n[[allowlists]]\npaths = [ """.*""" ]\n' >> "$R/.gitleaks.toml"
check allowlist-everything-red 1 'allowlist too wide'
# g) unicode-guard neutered → red
scaffold; sed -i 's/^BIDI_RE=.*/BIDI_RE=NEVERMATCH/' "$R/ci/unicode-guard.sh"
check neutered-unicode-guard-red 1 'unicode-guard: bidi override'
# h) .gitleaks.toml missing → cannot test → rc 2
scaffold; rm "$R/.gitleaks.toml"
check no-config-rc2 2 'missing'
# i) the selftest leaves nothing behind in the repo
scaffold; mkdir -p "$R/db/migrate"; (cd "$R" && bash ci/gate.sh --selftest >/dev/null 2>&1) || true
[ -z "$(cd "$R" && git status --porcelain -- db src 2>/dev/null)" ] && [ ! -e "$R/db/migrate/0001_selftest.sql" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL selftest left files in the repo: $(cd "$R" && git status --porcelain)" >&2; }

echo "tests/gate-selftest: $pass passed, $fail failed"
[ "$fail" = 0 ]
