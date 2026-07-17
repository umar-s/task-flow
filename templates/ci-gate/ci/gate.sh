#!/usr/bin/env bash
# gate.sh — run the full deterministic gate locally (CI parity).
#
#   ci/gate.sh            # scan working state; migration-guard needs GATE_BASE_REF
#   ci/gate.sh --staged   # scan the staged index (what pre-commit does)
#
# secret-scan uses a local `gitleaks` if present, else the official container.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git rev-parse --show-toplevel)
cd "$repo"
mode="${1:-}"

echo "== secret-scan (gitleaks) =="
if command -v gitleaks >/dev/null 2>&1; then
  if [ "$mode" = "--staged" ]; then
    gitleaks protect --staged --redact --no-banner -v
  else
    gitleaks detect --redact --no-banner -v
  fi
elif command -v docker >/dev/null 2>&1; then
  echo "gitleaks not on PATH; using ghcr.io/gitleaks/gitleaks container"
  docker run --rm -v "$repo:/repo" -w /repo ghcr.io/gitleaks/gitleaks:latest \
    detect --source /repo --redact --no-banner -v
else
  echo "gate: neither gitleaks nor docker available" >&2
  exit 2
fi

echo "== migration-guard =="
bash "$here/migration-guard.sh" "$mode"

echo "gate: OK"
