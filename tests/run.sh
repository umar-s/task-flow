#!/usr/bin/env bash
# tests/run.sh — the payload's negative controls (CLAUDE.md: a gate nobody has
# seen fail is not known to work). Repository-side only; never shipped.
# The scanner-backed suites share one pinned-gitleaks cache (one download per
# run); tests/gitleaks-fetch.sh uses its own because it tampers with the cache.
set -euo pipefail
cd "$(dirname "$0")/.."
# One scanner cache for the whole run, kept between runs: only the first run on
# a machine needs the network (tests/gitleaks-fetch.sh still uses a private copy
# of it — it tampers with the cache on purpose).
export GITLEAKS_CACHE_DIR="${GITLEAKS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/task-flow-tests/gitleaks}"
mkdir -p "$GITLEAKS_CACHE_DIR"
rc=0
for t in tests/*.sh; do            # every suite, so a new one cannot be forgotten
  [ "$t" = "tests/run.sh" ] && continue
  bash "$t" || rc=1
done
exit "$rc"
