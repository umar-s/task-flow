#!/usr/bin/env bash
# scan-text.sh — scan ONE file for secrets with the gate's gitleaks, before
# its content leaves the repo: a merge-request description, a tracker close
# comment, a release note, a pasted log. Scan-at-sink — the bytes scanned are
# exactly the bytes posted, so write the text to a file, run this on it, and
# post that same file.
#
#   ci/scan-text.sh path/to/comment.md
#
# Uses the same scanner resolution and pin as every other layer
# (ci/gitleaks-bin.sh). Rules come from the repo's .gitleaks.toml — including
# its path allowlists, which apply to THIS file's name: call the temp file
# something plain (`comment.md`), never `*.example` or anything under a
# fixtures dir, or the scan is a no-op that looks like a pass.
#
# Exit codes: 0 clean · 1 secret found (details on stderr, redacted) ·
# 2 config/infra (fails closed). gitleaks exits 1 for a fatal error too (a
# broken config), so "found something" is decided by its JSON report, not by
# the exit code alone.
set -euo pipefail

# Verdicts are byte comparisons, so the locale must not decide them: in tr_TR
# and az_AZ, `i` and `I` are not a case pair, and `grep -i` there stops
# matching lowercase `index`, `constraint`, `trigger`, `materialized`.
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
cfg="$repo/.gitleaks.toml"
file="${1:-}"
[ -n "$file" ] || { echo "usage: ci/scan-text.sh <file>" >&2; exit 2; }
[ -f "$file" ] && [ -r "$file" ] || { echo "scan-text: '$file' is not a readable file. Failing closed." >&2; exit 2; }
[ -r "$cfg" ] || { echo "scan-text: $cfg is missing or unreadable. Failing closed." >&2; exit 2; }

work=$(mktemp -d) || { echo "scan-text: cannot create a temp dir. Failing closed." >&2; exit 2; }
export GITLEAKS_RUN_DIR="${GITLEAKS_RUN_DIR:-$work}"
trap 'rm -rf "$work"' EXIT
GL="$(bash "$here/gitleaks-bin.sh")" || { echo "scan-text: cannot resolve gitleaks. Failing closed." >&2; exit 2; }

rpt="$work/report.json"
"$GL" dir "$file" --config "$cfg" --redact --no-banner --report-format json --report-path "$rpt" && rc=0 || rc=$?
case "$rc" in
  0) echo "scan-text: OK — $file" ;;
  1) if [ -s "$rpt" ] && ! grep -q '^\[\]$' "$rpt"; then
       echo "scan-text: SECRET in $file — do not post it; rotate the credential, then rewrite the text" >&2
     else
       # rc 1 with no report is gitleaks' FTL path (unreadable/invalid config)
       echo "scan-text: scanner exited 1 without a report — configuration error, not a clean file. Failing closed." >&2
       exit 2
     fi ;;
  *) echo "scan-text: scanner failed (rc=$rc) on $file. Failing closed." >&2; exit 2 ;;
esac
exit "$rc"
