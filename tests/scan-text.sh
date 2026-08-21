#!/usr/bin/env bash
# tests/scan-text.sh — negative controls for templates/ci-gate/ci/scan-text.sh.
# Needs network once (pinned gitleaks); set GITLEAKS_CACHE_DIR to reuse a cache.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GITLEAKS_CACHE_DIR="${GITLEAKS_CACHE_DIR:-$TMP/cache}" GITLEAKS_RUN_DIR="$TMP/run" GATE_PINNED_ONLY=1
pass=0; fail=0
# Credential-shaped, assembled at run time: a literal key in a tracked file
# would be flagged by this repository's own secret-scan (and by every consumer's).
SECRET="token: AKIA$(printf 'Q4U7W2R5T3Y6P2M4')"

# the script resolves the repo (and its .gitleaks.toml) from its own location, not from cwd
git init -q "$TMP/repo"; mkdir -p "$TMP/repo/ci"
cp "$ROOT"/templates/ci-gate/ci/*.sh "$TMP/repo/ci/"; cp "$ROOT/templates/ci-gate/.gitleaks.toml" "$TMP/repo/"
SCAN="$TMP/repo/ci/scan-text.sh"

check() {  # name expected file [env...]
  local name="$1" expect="$2" file="$3"; shift 3; local rc out
  out=$(env "$@" bash "$SCAN" "$file" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$out" >&2; fi
  LAST_OUT="$out"
}

cd "$TMP"   # cwd is outside the repo on purpose
printf 'Closed: tests 47/47, CI green (secret-scan, migration-guard).\n' > comment.md
check clean-comment 0 comment.md
printf 'Closed. Note for ops: %s\n' "$SECRET" > leak.md
check secret-in-comment 1 leak.md
printf '%s\n' "$LAST_OUT" | grep -q 'do not post it' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL message: $LAST_OUT" >&2; }
printf '%s\n' "$LAST_OUT" | grep -q "${SECRET#token: }" && { fail=$((fail+1)); echo "FAIL secret echoed unredacted" >&2; } || pass=$((pass+1))
check missing-file 2 nope.md
check no-argument 2 ""
chmod 000 leak.md; [ "$(id -u)" = 0 ] || check unreadable-file 2 leak.md; chmod 644 leak.md
# the documented by-design hole: the repo's path allowlist applies to THIS file's name
cp leak.md leak.example
check allowlisted-name-is-not-scanned 0 leak.example
# a broken .gitleaks.toml makes gitleaks exit 1 (FTL) with no report — that is infra, not "clean"
printf 'not a toml {{{\n' > "$TMP/repo/.gitleaks.toml"
check broken-config 2 comment.md
printf '%s\n' "$LAST_OUT" | grep -q 'without a report' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL broken-config message: $LAST_OUT" >&2; }
cp "$ROOT/templates/ci-gate/.gitleaks.toml" "$TMP/repo/"
rm "$TMP/repo/.gitleaks.toml.bak" 2>/dev/null || true
# a missing config is infra too
mv "$TMP/repo/.gitleaks.toml" "$TMP/cfg.bak"; check missing-config 2 comment.md; mv "$TMP/cfg.bak" "$TMP/repo/.gitleaks.toml"
# the scanner failing is not a clean file
mkdir -p "$TMP/badgl"; printf '#!/bin/sh\necho "gitleaks: simulated failure" >&2\nexit 3\n' > "$TMP/badgl/gitleaks"; chmod +x "$TMP/badgl/gitleaks"
check broken-scanner 2 comment.md PATH="$TMP/badgl:$PATH" GATE_PINNED_ONLY=0
# an inline gitleaks:allow on the line is honoured (same rules as the gate)
printf 'example key: %s  # gitleaks:allow\n' "$SECRET" > doc.md
check inline-allow 0 doc.md

echo "tests/scan-text: $pass passed, $fail failed"
[ "$fail" = 0 ]
