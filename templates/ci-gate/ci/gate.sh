#!/usr/bin/env bash
# gate.sh — run the full deterministic gate locally (CI parity).
#
#   ci/gate.sh            # scan working state; migration-guard needs GATE_BASE_REF
#   ci/gate.sh --staged   # scan the staged index (what pre-commit does)
#
# secret-scan uses a local `gitleaks` if present, else fetches a pinned,
# checksum-verified binary (ci/gitleaks-fetch.sh) — no docker required.
# GATE_PINNED_ONLY=1 ignores a gitleaks on PATH and always uses the pinned one
# (same version, same verdict as CI).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git rev-parse --show-toplevel)
cd "$repo"
mode="${1:-}"

echo "== secret-scan (gitleaks) =="
if [ "${GATE_PINNED_ONLY:-0}" != "1" ] && command -v gitleaks >/dev/null 2>&1; then
  GL=gitleaks
else
  echo "fetching pinned gitleaks (ci/gitleaks-fetch.sh)"
  export GITLEAKS_RUN_DIR
  GITLEAKS_RUN_DIR=$(mktemp -d)
  trap 'rm -rf "$GITLEAKS_RUN_DIR"' EXIT        # the per-call extraction dir
  GL="$(bash "$here/gitleaks-fetch.sh")"
fi
if [ "$mode" = "--staged" ]; then
  "$GL" protect --staged --redact --no-banner -v
else
  "$GL" detect --redact --no-banner -v
fi

echo "== migration-guard =="
bash "$here/migration-guard.sh" "$mode"

# Changed-line coverage runs against a report a test run produced, so it only
# makes sense on a real revision range — not on the staged index.
if [ "$mode" != "--staged" ]; then
  echo "== diff-coverage =="
  bash "$here/diff-coverage.sh"
fi

echo "gate: OK"
