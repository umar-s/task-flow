#!/usr/bin/env bash
# gitleaks-bin.sh — resolve THE scanner every gate layer uses, one way, in one
# place. Prints the binary path on stdout; all logs go to stderr.
#
#   GL="$(bash ci/gitleaks-bin.sh)"
#
# Resolution: a `gitleaks` already on PATH (yours, whatever version), unless
# GATE_PINNED_ONLY=1 — then the pinned, checksum-verified build from
# ci/gitleaks-fetch.sh, which is the version CI runs and therefore the verdict
# CI will give. Callers that get a fetched binary must remove the extraction
# dir: export GITLEAKS_RUN_DIR to a directory you own and delete it (gate.sh,
# scan-text.sh and pre-push.sh all trap it; the shell CI variant points it at
# the job workspace).
#
# Why one script: three copies of this block drifted apart once already — a
# local hook and CI must never resolve different binaries, or "green locally"
# and "green in CI" stop meaning the same thing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
log() { printf 'gitleaks-bin: %s\n' "$*" >&2; }

if [ "${GATE_PINNED_ONLY:-0}" != "1" ] && command -v gitleaks >/dev/null 2>&1; then
  log "using gitleaks on PATH: $(command -v gitleaks) ($(gitleaks version 2>/dev/null || echo 'version unknown'))"   # lint: allow — the version string is a log line, not a verdict
  command -v gitleaks
  exit 0
fi
[ -f "$here/gitleaks-fetch.sh" ] || { log "$here/gitleaks-fetch.sh missing and no gitleaks on PATH — failing closed"; exit 2; }
bash "$here/gitleaks-fetch.sh"
