#!/usr/bin/env bash
# gate.sh — run the full deterministic gate locally (CI parity).
#
#   ci/gate.sh             # scan working state; migration-guard needs GATE_BASE_REF
#   ci/gate.sh --staged    # scan the staged index (what pre-commit does)
#   ci/gate.sh --selftest  # prove the gate can FAIL: known-bad fixtures in a
#                          # throwaway repo must go red (and known-good, green)
#
# secret-scan uses a local `gitleaks` if present, else fetches a pinned,
# checksum-verified binary (ci/gitleaks-fetch.sh) — no docker required.
# GATE_PINNED_ONLY=1 ignores a gitleaks on PATH and always uses the pinned one
# (same version, same verdict as CI).
set -euo pipefail

# Verdicts are byte comparisons, so the locale must not decide them: in tr_TR
# and az_AZ, `i` and `I` are not a case pair, and `grep -i` there stops
# matching lowercase `index`, `constraint`, `trigger`, `materialized`.
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git rev-parse --show-toplevel)
cd "$repo"
mode="${1:-}"

SELFTEST_TMP=""
cleanup() { [ "${GATE_OWNS_RUN_DIR:-0}" = 1 ] && rm -rf "$GITLEAKS_RUN_DIR"; [ -n "$SELFTEST_TMP" ] && rm -rf "$SELFTEST_TMP"; return 0; }
trap cleanup EXIT

# One scanner resolution for every layer (ci/gitleaks-bin.sh).
if [ -z "${GITLEAKS_RUN_DIR:-}" ]; then
  export GITLEAKS_RUN_DIR; GITLEAKS_RUN_DIR=$(mktemp -d); GATE_OWNS_RUN_DIR=1
fi
GL="$(bash "$here/gitleaks-bin.sh")" || { echo "gate: cannot resolve gitleaks (nothing on PATH and the pinned fetch failed) — failing closed." >&2; exit 2; }

# ---------------------------------------------------------------------------
# --selftest: a gate nobody has seen fail is not known to be wired up. Every
# control below is a known-bad (or known-good) input judged by the SAME
# scripts, the SAME scanner and the SAME .gitleaks.toml this repo runs, inside
# a throwaway repo. A mis-set MIGRATION_DIRS, an allowlist that swallows
# everything, a scanner that never started — all read exactly like a clean
# diff on a green run; here they read as a failed control.
# ---------------------------------------------------------------------------
if [ "$mode" = "--selftest" ]; then
  MIGRATION_DIRS="${MIGRATION_DIRS:-migrations db/migrate db/migration prisma/migrations}"
  first_dir="${MIGRATION_DIRS%% *}"
  ok=0; bad=0
  result() {  # name expected actual [must-match-in-output] output
    local name="$1" expect="$2" got="$3" want="${4:-}" out="${5:-}"
    if [ "$got" = "$expect" ] && { [ -z "$want" ] || printf '%s' "$out" | grep -q -- "$want"; }; then
      printf '  ok    %-34s rc=%s\n' "$name" "$got"; ok=$((ok+1))
    else
      printf '  FAIL  %-34s rc=%s expected=%s%s\n' "$name" "$got" "$expect" "${want:+ (and output containing '$want')}"; bad=$((bad+1))
      [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/        | /'
    fi
  }
  [ -f "$repo/.gitleaks.toml" ] || { echo "selftest: $repo/.gitleaks.toml missing — nothing to test the scanner against" >&2; exit 2; }
  SELFTEST_TMP=$(mktemp -d) || { echo "selftest: cannot create a temp dir" >&2; exit 2; }
  T="$SELFTEST_TMP/repo"
  # The throwaway repo must not inherit the user's git config: a commit hook
  # from init.templateDir, commit.gpgsign, or a global core.hooksPath would
  # make the selftest fail for reasons that have nothing to do with the gate.
  g() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$T" \
          -c user.name=selftest -c user.email=selftest@localhost \
          -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q --template= "$T" \
    || { echo "selftest: git init failed in $T" >&2; exit 2; }
  git -C "$T" symbolic-ref HEAD refs/heads/main
  g commit -q --allow-empty -m init
  guard() { (cd "$T" && MIGRATION_DIRS="$MIGRATION_DIRS" bash "$here/migration-guard.sh" --staged 2>&1); }
  uguard() { (cd "$T" && bash "$here/unicode-guard.sh" --staged 2>&1); }
  stage() { mkdir -p "$T/$(dirname "$1")"; printf '%b' "$2" > "$T/$1"; g add -A; }
  unstage() { g rm -rq --cached . >/dev/null 2>&1 || true; rm -rf "${T:?}/${first_dir%%/*}" "$T/src"; }   # lint: allow — throwaway repo
  echo "== selftest (throwaway repo; MIGRATION_DIRS=\"$MIGRATION_DIRS\", scanner: $GL) =="

  present=0; for d in $MIGRATION_DIRS; do [ -d "$repo/$d" ] && present=1; done
  [ "$present" = 1 ] || echo "  warn  none of MIGRATION_DIRS exists in this repo — migration-guard is watching empty dirs (fine for a repo without migrations; otherwise set MIGRATION_DIRS)"

  stage "$first_dir/0001_selftest.sql" 'DROP TABLE legacy;\n'
  out=$(guard) && rc=0 || rc=$?; result "migration-guard: unmarked DROP" 1 "$rc" 'FAIL \[destructive\]' "$out"; unstage
  stage "$first_dir/0002_selftest.sql" '-- destructive: approved\nDROP TABLE legacy;\n'
  out=$(guard) && rc=0 || rc=$?; result "migration-guard: marker w/o reason" 1 "$rc" 'carries no reason' "$out"; unstage
  stage "$first_dir/0003_selftest.sql" '-- destructive: approved (SELFTEST-1: archived)\nDROP TABLE legacy;\n'
  out=$(guard) && rc=0 || rc=$?; result "migration-guard: marked DROP" 0 "$rc" '' "$out"; unstage
  stage "$first_dir/0004_selftest.sql" 'CREATE TABLE t (id int);\n'
  out=$(guard) && rc=0 || rc=$?; result "migration-guard: clean migration" 0 "$rc" '' "$out"
  g commit -qm "committed migration"
  printf 'ALTER TABLE t ADD COLUMN c int;\n' >> "$T/$first_dir/0004_selftest.sql"; g add -A
  out=$(guard) && rc=0 || rc=$?; result "migration-guard: edit committed one" 1 "$rc" 'FAIL \[immutable\]' "$out"; unstage
  mkdir -p "$SELFTEST_TMP/badbin"; printf '#!/bin/sh\necho "awk: simulated failure" >&2\nexit 2\n' > "$SELFTEST_TMP/badbin/awk"; chmod +x "$SELFTEST_TMP/badbin/awk"
  stage "$first_dir/0005_selftest.sql" 'DROP TABLE legacy;\n'
  out=$(PATH="$SELFTEST_TMP/badbin:$PATH" guard) && rc=0 || rc=$?; result "migration-guard: broken awk fails closed" 2 "$rc" '' "$out"; unstage

  # Credential-shaped, assembled at run time so this file never carries a
  # literal that the gate (ours or yours) would flag in its own source.
  stage "src/config.py" "aws_key = \"AKIA$(printf 'Q4U7W2R5T3Y6P2M4')\"\n"
  out=$(cd "$T" && "$GL" protect --staged --redact --no-banner --config "$repo/.gitleaks.toml" 2>&1) && rc=0 || rc=$?
  result "secret-scan: credential-shaped line" 1 "$rc" '' "$out"; unstage
  [ "$rc" = 0 ] && echo "        ^ a secret passed: .gitleaks.toml allowlist too wide, or the scanner is not the one you think"
  stage "src/ok.py" 'x = 1\n'
  out=$(cd "$T" && "$GL" protect --staged --redact --no-banner --config "$repo/.gitleaks.toml" 2>&1) && rc=0 || rc=$?
  result "secret-scan: clean file" 0 "$rc" '' "$out"; unstage

  stage "src/auth.js" '// check admin \xe2\x80\xae { return; }\n'
  out=$(uguard) && rc=0 || rc=$?; result "unicode-guard: bidi override" 1 "$rc" 'bidi' "$out"; unstage
  stage "src/i18n.md" 'family: \xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9 — «ок»\n'
  out=$(uguard) && rc=0 || rc=$?; result "unicode-guard: ZWJ emoji + prose" 0 "$rc" '' "$out"; unstage

  hookdir=$(git rev-parse --git-path hooks)
  if [ -x "$hookdir/pre-push" ]; then
    echo "  ok    pre-push hook installed"
  elif [ -f "$hookdir/pre-push" ]; then
    echo "  warn  $hookdir/pre-push exists but is not executable — git ignores it silently (chmod +x)"
  else
    echo "  warn  no pre-push hook in $hookdir — the pre-push layer is not wired (pre-commit install, or cp ci/pre-push.sh)"
  fi
  echo "selftest: $ok ok, $bad failed"
  if [ "$bad" != 0 ]; then echo "selftest: the gate did NOT fail where it must — do not trust its green until this is fixed" >&2; exit 1; fi
  echo "gate: selftest OK — every known-bad input reached the failure path (this proves wiring, not coverage)"
  exit 0
fi

echo "== secret-scan (gitleaks) =="
if [ "$mode" = "--staged" ]; then
  # `protect --staged` reads the index through git, so a `-diff` attribute can
  # hide a file from it and there is no --log-opts to override that here; the
  # CI scan (and pre-push) pass --text and catch it. Documented in ci/README.md.
  "$GL" protect --staged --redact --no-banner -v
else
  # Same validation as the CI templates, with the command gitleaks runs: git
  # failing inside gitleaks reads as "no leaks found" (rc 0), and --diff-merges
  # needs git >= 2.31.
  if ! git log --text --diff-merges=first-parent --max-count=1 --format=%H --all >/dev/null; then
    echo "gate: this git cannot run 'log --text --diff-merges=first-parent' (needs git >= 2.31) — failing closed" >&2
    exit 2
  fi
  "$GL" detect --redact --no-banner -v --log-opts="--text --diff-merges=first-parent"
fi

echo "== migration-guard =="
bash "$here/migration-guard.sh" "$mode"

echo "== unicode-guard =="
bash "$here/unicode-guard.sh" "$mode"

# Changed-line coverage runs against a report a test run produced, so it only
# makes sense on a real revision range — not on the staged index.
if [ "$mode" != "--staged" ]; then
  echo "== diff-coverage =="
  bash "$here/diff-coverage.sh"
fi

echo "gate: OK"
