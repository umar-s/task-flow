#!/usr/bin/env bash
# tests/agents-templates.sh — templates/agents: the execpolicy rules decide
# exactly what their header promises (including the residue they cannot see),
# a broken rule example fails to load, and the TOML templates parse.
# The execpolicy half needs Codex CLI on PATH; without it that half prints
# SKIPPED locally — a skipped check is named, never counted as passed — and
# fails under CI, where .github/workflows/check.yml installs the pinned CLI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
AG="$ROOT/templates/agents"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0; skipped=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

# TOML templates parse (tomllib: Python 3.11+, whichever python3.x has it).
PY=""; for c in python3 python3.13 python3.12 python3.11; do
  command -v "$c" >/dev/null && "$c" -c 'import tomllib' 2>/dev/null && { PY="$c"; break; }   # lint: allow — probing for an interpreter
done
if [ -n "$PY" ]; then
  for f in "$AG/.codex/agents/reviewer.toml" "$AG/.codex/config.toml.skeleton"; do
    "$PY" -I -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$f" && ok || bad "$f does not parse as TOML"
  done
  "$PY" -I -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb")); assert d["sandbox_mode"]=="read-only" and d["developer_instructions"].strip() and d["name"]=="reviewer"' "$AG/.codex/agents/reviewer.toml" \
    && ok || bad "reviewer.toml: not a read-only role with developer_instructions"
elif [ -n "${CI:-}" ]; then
  bad "no python3 with tomllib under CI — the TOML templates would not be parsed"
else
  skipped=$((skipped+1)); echo "tests/agents-templates: TOML parse SKIPPED (no python3 with tomllib)"
fi

if command -v codex >/dev/null; then
  decide() { codex execpolicy check --rules "$1" -- "${@:2}" | "${PY:-python3}" -I -c 'import sys,json; print(json.load(sys.stdin).get("decision","none"))'; }
  R="$AG/.codex/rules/git.rules"
  while IFS='|' read -r want cmd; do
    # shellcheck disable=SC2086 — the command is word-split on purpose
    got=$(decide "$R" $cmd) || got="error"
    [ "$got" = "$want" ] && ok || bad "git.rules: '$cmd' → $got, expected $want"
  done <<'EOF'
allow|git commit -m x
prompt|git push origin feature/x
forbidden|git push --force origin main
forbidden|git push -f
forbidden|git push --force-with-lease
forbidden|git push --delete origin x
prompt|git push origin main --force
prompt|git push --force-with-lease=refs/heads/main origin HEAD:main
prompt|git push -fu origin main
none|glab mr create --fill
none|git reset --hard
EOF
  for cmd in "git push" "git push origin HEAD" "git push --force-with-lease=x" "git push -fu" "git push origin +main"; do
    # shellcheck disable=SC2086
    got=$(decide "$R" $cmd) || got="error"
    [ "$got" != allow ] && ok || bad "git.rules auto-allows '$cmd' — no push may leave the sandbox without a person"
  done
  sed 's/match = \[\["git", "push", "--force", "origin", "main"\]/match = [["git", "pull"]/' "$R" > "$TMP/bad.rules"
  cmp -s "$R" "$TMP/bad.rules" && bad "the negative-control edit did not apply"
  codex execpolicy check --rules "$TMP/bad.rules" -- git push >/dev/null 2>&1 && bad "a rule whose match example does not match still loads" || ok
elif [ -n "${CI:-}" ]; then
  bad "codex not on PATH under CI — the execpolicy checks would not run (check.yml installs the pinned CLI)"
else
  skipped=$((skipped+1)); echo "tests/agents-templates: execpolicy checks SKIPPED (codex not on PATH)"
fi

echo "tests/agents-templates: $pass passed, $fail failed, $skipped skipped"
[ "$fail" = 0 ]
