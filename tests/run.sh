#!/usr/bin/env bash
# tests/run.sh — the payload's negative controls (CLAUDE.md: a gate nobody has
# seen fail is not known to work). Repository-side only; never shipped.
# The scanner-backed suites share one pinned-gitleaks cache (one download per
# run); tests/gitleaks-fetch.sh uses its own because it tampers with the cache.
set -euo pipefail
cd "$(dirname "$0")/.."
CACHE=$(mktemp -d); trap 'rm -rf "$CACHE"' EXIT
export GITLEAKS_CACHE_DIR="${GITLEAKS_CACHE_DIR:-$CACHE}"
rc=0
for t in tests/*.sh; do            # every suite, so a new one cannot be forgotten
  [ "$t" = "tests/run.sh" ] && continue
  bash "$t" || rc=1
done
exit "$rc"
