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
name="$(basename "$root")"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || die "gh cannot read this repository"
[ -n "$base" ] || base="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)" || die "gh cannot read the default branch"

if [ ${#issues[@]} -eq 0 ]; then
  labelled="$(gh issue list --state open --limit 200 --json number,labels \
    -q '.[] | select([.labels[].name] | any(. == "builder:claude" or . == "builder:codex")) | .number')" \
    || die "gh cannot list the issues"
  for n in $labelled; do
    open="$(gh api "repos/$repo/issues/$n/dependencies/blocked_by" -q '[.[] | select(.state == "open")] | length')" \
      || die "cannot read the blockers of #$n — refusing to guess that it is ready"
    [ "$open" = 0 ] && issues+=("$n")
  done
  [ ${#issues[@]} -gt 0 ] || { echo "task-wave: no ready task in $repo (open, builder:claude|codex label, no open blocker)"; exit 0; }
fi

session="wave-$name"
[ $dry = 1 ] || git -C "$root" fetch -q origin "$base" || die "cannot fetch origin/$base"
started=0
for n in "${issues[@]}"; do
  builder="$(gh issue view "$n" --json labels -q '[.labels[].name | select(. == "builder:claude" or . == "builder:codex")][0] // ""')" \
    || die "gh cannot read #$n"
  case "$builder" in
    builder:claude) cmd="claude $(printf %q "/task-flow:task #$n")" ;;
    builder:codex)  cmd="codex $(printf %q "\$task-flow:task #$n")" ;;
    *) echo "task-wave: #$n has no builder:claude or builder:codex label — skipped"; continue ;;
  esac
  wt="$(dirname "$root")/$name-$n"; br="task-$n"
  if [ -d "$wt" ]; then how="worktree exists — resuming in it"
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$br"; then how="git worktree add $wt $br   (branch exists)"
  else how="git worktree add $wt -b $br origin/$base"; fi
  printf '#%s %s → %s\n    %s\n    tmux window #%s: %s\n' "$n" "$builder" "$wt" "$how" "$n" "$cmd"
  [ $dry = 1 ] && continue
  if [ ! -d "$wt" ]; then
    if git -C "$root" show-ref --verify --quiet "refs/heads/$br"; then git -C "$root" worktree add -q "$wt" "$br"
    else git -C "$root" worktree add -q "$wt" -b "$br" "origin/$base"; fi
  fi
  if tmux has-session -t "=$session" 2>/dev/null; then   # lint: allow — "no session" is the answer, not an error
    tmux new-window -t "=$session" -n "#$n" -c "$wt" "$cmd"
  else
    tmux new-session -d -s "$session" -n "#$n" -c "$wt" "$cmd"
  fi
  started=$((started+1))
done
if [ $dry = 1 ]; then echo "task-wave: dry run — nothing created"
elif [ $started -gt 0 ]; then echo "task-wave: $started session(s) in tmux — attach with: tmux attach -t $session"; fi
