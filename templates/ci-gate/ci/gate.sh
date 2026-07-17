#!/usr/bin/env bash
# gate.sh — run the full deterministic gate locally (CI parity).
#
#   ci/gate.sh            # scan working state; migration-guard needs GATE_BASE_REF
#   ci/gate.sh --staged   # scan the staged index (what pre-commit does)
#
# secret-scan uses a local `gitleaks` if present, else fetches a pinned,
# checksum-verified binary (ci/gitleaks-fetch.sh) — no docker required.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git rev-parse --show-toplevel)
cd "$repo"
mode="${1:-}"

echo "== secret-scan (gitleaks) =="
if command -v gitleaks >/dev/null 2>&1; then
  GL=gitleaks
else
  echo "gitleaks not on PATH; fetching pinned binary"
  GL="$(bash "$here/gitleaks-fetch.sh")"
fi
if [ "$mode" = "--staged" ]; then
  "$GL" protect --staged --redact --no-banner -v
else
  "$GL" detect --redact --no-banner -v
fi

echo "== migration-guard =="
bash "$here/migration-guard.sh" "$mode"

echo "gate: OK"
