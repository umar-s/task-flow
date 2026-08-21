#!/usr/bin/env bash
# base-ref.sh — resolve the revision every range-based layer diffs against, in
# one place (migration-guard, unicode-guard and diff-coverage must never
# disagree about what "this change" is, and a new CI platform must be taught
# once, not three times).
#
#   BASE=$(bash ci/base-ref.sh) || exit 2
#
# Order: GATE_BASE_REF · GitLab MR (CI_MERGE_REQUEST_DIFF_BASE_SHA) · GitHub PR
# (origin/$GITHUB_BASE_REF). Nothing resolvable, or a base not present in the
# clone (a shallow fetch), is exit 2 — "I could not tell what changed" is never
# an empty change set.
set -euo pipefail
log() { printf '%s: %s\n' "${GATE_LAYER:-base-ref}" "$*" >&2; }

BASE="${GATE_BASE_REF:-}"
if [ -z "$BASE" ]; then
  if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then
    BASE="$CI_MERGE_REQUEST_DIFF_BASE_SHA"          # GitLab MR pipeline
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    BASE="origin/${GITHUB_BASE_REF}"                # GitHub PR
  fi
fi
if [ -z "$BASE" ]; then
  log "cannot resolve base ref (set GATE_BASE_REF). Failing closed."
  exit 2
fi
if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  log "base '$BASE' not in clone — need full history (GIT_DEPTH=0 / fetch-depth: 0). Failing closed."
  exit 2
fi
# A base that resolves to HEAD makes every range empty, and every range layer
# then reports OK on a change it never looked at — one CI variable
# (GATE_BASE_REF=HEAD) would switch off migration-guard, unicode-guard and
# diff-coverage at once. An empty range from a real base is fine; a base that
# IS the tip is a configuration error.
if [ "$(git rev-parse "${BASE}^{commit}")" = "$(git rev-parse 'HEAD^{commit}')" ]; then
  log "base '$BASE' is the same commit as HEAD — that is not a base, it is an off switch for every range layer. Failing closed."
  exit 2
fi
printf '%s\n' "$BASE"
