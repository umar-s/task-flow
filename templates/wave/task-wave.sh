#!/usr/bin/env bash
# task-wave.sh — start one wave of task-flow tasks side by side: every ready
# task gets its own git worktree and its own interactive session in a tmux
# window — Claude Code or Codex, by the issue's builder:* label.
#
#   bash scripts/task-wave.sh [--dry-run] [--base <branch>] [<issue>...]
#
# Run it from the repository (copy this file to scripts/ once). Tracker: GitHub
# Issues through an authenticated `gh`. With no issue numbers it takes the ready
# set — open issues carrying builder:claude or builder:codex whose blocked-by
# issues are all closed. A task whose worktree already exists is resumed in it.
# Sessions stay interactive — `task` asks on ingest and before merging, so
# attach (`tmux attach -t wave-<repo>`) and answer each window. Nothing is
# merged, pushed or deleted here.
set -euo pipefail

die() { echo "task-wave: $*" >&2; exit 2; }
dry=0; base=""; issues=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --base) [ $# -ge 2 ] || die "--base needs a branch"; base="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ "$1" =~ ^#?[0-9]+$ ]] || die "not an issue number: $1"; issues+=("${1#\#}"); shift ;;
  esac
done

command -v gh >/dev/null || die "gh is not on PATH"
[ $dry = 1 ] || command -v tmux >/dev/null || die "tmux is not on PATH (try --dry-run to see the plan)"
root="$(git rev-parse --show-toplevel)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"; name="$(basename "$root")"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || die "gh cannot read this repository"
[ -n "$base" ] || base="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)" || die "gh cannot read the default branch"

# The ready set: every open issue with a builder label (server-side label filter,
# all pages — no count limit), pull requests excluded, then its blockers.
if [ ${#issues[@]} -eq 0 ]; then
  labelled=""
  for label in builder:claude builder:codex; do
    page="$(gh api --paginate "repos/$repo/issues?state=open&per_page=100&labels=$label" \
      -q '.[] | select(.pull_request == null) | .number')" || die "gh cannot list the issues labelled $label"
    labelled="$labelled $page"
  done
  for n in $(printf '%s\n' $labelled | sort -nu); do
    open="$(gh api "repos/$repo/issues/$n/dependencies/blocked_by" -q '[.[] | select(.state == "open")] | length')" \
      || die "cannot read the blockers of #$n — refusing to guess that it is ready"
    [ "$open" = 0 ] && issues+=("$n")
  done
  [ ${#issues[@]} -gt 0 ] || { echo "task-wave: no ready task in $repo (open, builder:claude|codex label, no open blocker)"; exit 0; }
fi

# Is $1 a worktree of this repository, checked out on branch $2? (canonical paths)
our_worktree() {
  local want; want="$(cd "$1" && pwd -P)"
  git -C "$root" worktree list --porcelain | awk -v w="$want" -v b="refs/heads/$2" '
    $1 == "worktree" { cur = substr($0, 10) }
    $1 == "branch" && cur == w && $2 == b { found = 1 }
    END { exit !found }'
}

# Plan every task first; anything that cannot be started safely stops the run
# before a single worktree or window exists.
plan_n=(); plan_wt=(); plan_mode=(); plan_cmd=()
for n in "${issues[@]}"; do
  builder="$(gh issue view "$n" --json labels -q '[.labels[].name | select(. == "builder:claude" or . == "builder:codex")][0] // ""')" \
    || die "gh cannot read #$n"
  case "$builder" in
    builder:claude) cmd="claude $(printf %q "/task-flow:task #$n")" ;;
    builder:codex)  cmd="codex $(printf %q "\$task-flow:task #$n")" ;;
    *) echo "task-wave: #$n has no builder:claude or builder:codex label — skipped"; continue ;;
  esac
  wt="$(dirname "$root")/$name-$n"; br="task-$n"
  if [ -e "$wt" ]; then
    our_worktree "$wt" "$br" || die "$wt exists but is not this repository's worktree on $br — move it or start #$n by hand"
    mode=resume; how="worktree on $br exists — resuming in it"
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$br"; then
    mode=branch; how="git worktree add $wt $br   (branch exists)"
  else
    mode=new; how="git worktree add $wt -b $br origin/$base"
  fi
  printf '#%s %s → %s\n    %s\n    tmux window #%s: %s\n' "$n" "$builder" "$wt" "$how" "$n" "$cmd"
  plan_n+=("$n"); plan_wt+=("$wt"); plan_mode+=("$mode"); plan_cmd+=("$cmd")
done
[ ${#plan_n[@]} -gt 0 ] || exit 0
[ $dry = 1 ] && { echo "task-wave: dry run — nothing created"; exit 0; }

git -C "$root" fetch -q origin "$base" || die "cannot fetch origin/$base"
session="wave-$name"; i=0
while [ $i -lt ${#plan_n[@]} ]; do
  n="${plan_n[$i]}"; wt="${plan_wt[$i]}"; cmd="${plan_cmd[$i]}"
  case "${plan_mode[$i]}" in
    new)    git -C "$root" worktree add -q "$wt" -b "task-$n" "origin/$base" ;;
    branch) git -C "$root" worktree add -q "$wt" "task-$n" ;;
  esac
  if tmux has-session -t "=$session" 2>/dev/null; then   # lint: allow — "no session" is the answer, not an error
    tmux new-window -t "=$session" -n "#$n" -c "$wt" "$cmd"
  else
    tmux new-session -d -s "$session" -n "#$n" -c "$wt" "$cmd"
  fi
  i=$((i+1))
done
echo "task-wave: ${#plan_n[@]} session(s) in tmux — attach with: tmux attach -t $session"
