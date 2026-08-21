#!/usr/bin/env bash
# pre-push.sh — the last local layer: scan the commits about to leave this
# machine for secrets, per ref, BEFORE the remote has them. Catches what the
# commit hook never saw — `git commit --no-verify`, an amend, a rebase, history
# made on another machine — while the secret is still private.
#
# Two ways to install:
#   pre-commit   .pre-commit-config.yaml carries this hook with
#                `stages: [pre-push]` and `default_install_hook_types`, so a
#                plain `pre-commit install` wires it. pre-commit hands over ONE
#                ref via PRE_COMMIT_FROM_REF / PRE_COMMIT_TO_REF; a push of
#                several refs is scanned for the first one only (its contract).
#   native       cp ci/pre-push.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push
#                git feeds `<local ref> <local sha> <remote ref> <remote sha>`
#                lines on stdin; every ref is scanned.
#
# Range per ref — what the push actually sends, never less:
#   remote sha known and present locally  → remote..local (new commits, incl. an amend)
#   new branch / remote sha unknown here  → local --not --remotes=<remote>
#                                           (everything this remote does not have
#                                           yet — including commits sitting
#                                           unpushed on another local branch,
#                                           which a merge-base against the
#                                           default branch would have missed)
#   ref deletion                          → nothing to scan
# The range is validated with `git rev-list` BEFORE the scan: gitleaks exits 0
# when the git command inside it fails ("0 commits scanned, no leaks found"),
# so an unresolvable range would otherwise read exactly like a clean push.
# Every scan carries `--text` (a `-diff` attribute in .gitattributes would
# otherwise hide a file from the scanner) and `--diff-merges=first-parent`
# (without it a secret added in a merge commit is invisible to `git log -p`).
#
# Bypass: GATE_PREPUSH_SKIP="<sha>: <reason>" where <sha> is the (≥7 hex) local
# sha this push sends — so a value exported once in a shell profile does not
# bypass the next push — and <reason> is non-empty. It is appended to
# $GIT_DIR/gate-bypass.log (local, never committed, readable in a post-mortem).
# `git push --no-verify` skips this hook entirely and leaves no record; the CI
# secret-scan is the backstop for that. This layer is a convenience for honest
# users, not a boundary.
#
# Exit codes: 0 ok / bypassed · 1 secret found · 2 cannot evaluate (blocks).
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
gitdir=$(git rev-parse --git-dir)
remote="${1:-${PRE_COMMIT_REMOTE_NAME:-origin}}"
zero='^0+$'

# --- collect the refs being pushed -------------------------------------------
# Each entry: "<label>|<sha>|<rev-list args>" (args go verbatim to `git
# rev-list` for validation and, as one string, to gitleaks --log-opts).
entries=()
label_of() { printf '%s' "$1" | sed 's|^refs/heads/||'; }
range_for() {        # local_sha remote_sha → rev-list args on stdout
  local local_sha="$1" remote_sha="${2:-}"
  if [ -n "$remote_sha" ] && ! [[ "$remote_sha" =~ $zero ]] && git rev-parse --verify --quiet "${remote_sha}^{commit}" >/dev/null; then
    printf '%s..%s' "$remote_sha" "$local_sha"
  else
    printf '%s --not --remotes=%s' "$local_sha" "$remote"
  fi
}

if [ -n "${PRE_COMMIT_TO_REF:-}${PRE_COMMIT_FROM_REF:-}${PRE_COMMIT_REMOTE_NAME:-}${PRE_COMMIT_REMOTE_URL:-}" ]; then
  # pre-commit mode. FROM/TO are both absent when pre-commit decided "all
  # files" (nothing of this ref exists on the remote) — then fall back to the
  # same "everything the remote does not have" range as the native path.
  to="${PRE_COMMIT_TO_REF:-}"; from="${PRE_COMMIT_FROM_REF:-}"
  [ -n "$to" ] || to=$(git rev-parse HEAD)
  if [ -n "$from" ] && ! [[ "$from" =~ $zero ]]; then args="$from..$to"; else args=$(range_for "$to"); fi
  entries+=("$(label_of "${PRE_COMMIT_LOCAL_BRANCH:-HEAD}")|$to|$args")
else
  # native mode: git's stdin lines
  while read -r local_ref local_sha remote_ref remote_sha; do
    [ -n "${local_sha:-}" ] || continue
    [[ "$local_sha" =~ $zero ]] && continue                        # deleting a remote ref: nothing goes out
    entries+=("$(label_of "$local_ref")|$local_sha|$(range_for "$local_sha" "${remote_sha:-}")")
  done
fi

if [ "${#entries[@]}" -eq 0 ]; then echo "pre-push: nothing to scan"; exit 0; fi

# --- bypass: one push, one reason, on the record ------------------------------
if [ -n "${GATE_PREPUSH_SKIP:-}" ]; then
  bypass=0; want=""; why=""
  if [[ "$GATE_PREPUSH_SKIP" =~ ^([0-9a-fA-F]{7,40})[[:space:]:]+(.+)$ ]]; then
    want=$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-F' 'a-f'); why="${BASH_REMATCH[2]}"
    for e in "${entries[@]}"; do
      sha="${e#*|}"; sha="${sha%%|*}"
      case "$sha" in "$want"*) bypass=1 ;; esac
    done
  fi
  if [ "$bypass" = 1 ]; then
    who=$(git config user.email || true)   # lint: allow — identity is for the log line only
    labels=""; for e in "${entries[@]}"; do labels="$labels${labels:+ }${e%%|*}"; done
    printf '%s %s refs=[%s] sha=%s reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${who:-${USER:-?}}" "$labels" "$want" "$why" >> "$gitdir/gate-bypass.log"
    echo "pre-push: BYPASSED — recorded in $gitdir/gate-bypass.log (reason: $why)" >&2
    exit 0
  fi
  first="${entries[0]#*|}"; first="${first%%|*}"
  echo "pre-push: GATE_PREPUSH_SKIP does not name this push — scanning anyway. To bypass THIS push: GATE_PREPUSH_SKIP=\"$(printf '%.12s' "$first"): <reason>\"" >&2
fi

# --- scanner: same resolution and pin as every other layer ---------------------
[ -f "$repo/ci/gitleaks-bin.sh" ] || { echo "pre-push: $repo/ci/gitleaks-bin.sh not in the checked-out tree — blocking (fail closed)." >&2; exit 2; }
[ -f "$repo/.gitleaks.toml" ] || { echo "pre-push: $repo/.gitleaks.toml missing — blocking (fail closed)." >&2; exit 2; }
export GITLEAKS_RUN_DIR="${GITLEAKS_RUN_DIR:-$(mktemp -d)}"
trap 'rm -rf "$GITLEAKS_RUN_DIR"' EXIT
GL="$(bash "$repo/ci/gitleaks-bin.sh")" || { echo "pre-push: cannot resolve gitleaks — blocking (fail closed)." >&2; exit 2; }

fail=0
for e in "${entries[@]}"; do
  label="${e%%|*}"; args="${e##*|}"
  # shellcheck disable=SC2086 -- built above; the words are the rev-list range
  if ! git -C "$repo" rev-list $args >/dev/null; then
    echo "pre-push: git cannot resolve the range for '$label' ($args) — blocking (fail closed); gitleaks would have called it clean." >&2
    exit 2
  fi
  echo "pre-push: secret-scan $label ($args)"
  "$GL" detect --source "$repo" --config "$repo/.gitleaks.toml" --redact --no-banner \
        --log-opts="--text --diff-merges=first-parent $args" && rc=0 || rc=$?
  case "$rc" in
    0) ;;
    1) echo "pre-push: SECRET in commits of '$label' — push blocked. Rotate it, then rewrite the commit (ci/README.md → When secret-scan fires)." >&2; fail=1 ;;
    *) echo "pre-push: scanner failed (rc=$rc) on '$label' — blocking (fail closed)." >&2; exit 2 ;;
  esac
done
[ "$fail" = 0 ] && echo "pre-push: OK"
exit "$fail"
