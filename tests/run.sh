#!/usr/bin/env bash
# tests/run.sh — the payload's negative controls (CLAUDE.md: a gate nobody has
# seen fail is not known to work). Repository-side only; never shipped.
set -euo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/migration-guard.sh tests/gitleaks-fetch.sh; do
  bash "$t" || rc=1
done
exit "$rc"
