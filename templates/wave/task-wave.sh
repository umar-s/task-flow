#!/usr/bin/env bash
# task-wave.sh — start one wave of task-flow tasks side by side: every ready
# task gets its own git worktree and its own interactive session in a tmux
# window — Claude Code or Codex, by the issue's builder:* label or tag.
#
#   bash scripts/task-wave.sh [--dry-run] [--base <branch>] [<issue>...]                    # GitHub Issues
#   bash scripts/task-wave.sh --tracker youtrack [--project KEY] [--epic ID] [--dry-run] [--base <branch>] [<ID>...]
#
# Run it from the repository (copy this file to scripts/ once). Nothing is merged,
# pushed or deleted here. Sessions stay interactive — `task` asks on ingest and
# before merging, so attach (`tmux attach -t wave-<repo>`) and answer each window.
#   github (default; or TASK_WAVE_TRACKER): an authenticated `gh`. Ready = open
#     issues labelled builder:claude or builder:codex whose blocked-by issues are
#     all closed. Base = the repository's default branch.
#   youtrack: `curl` + `jq`; YOUTRACK_URL (https://…, the instance root),
#     YOUTRACK_TOKEN_VAR = the NAME of the variable holding the token (default
#     YOUTRACK_TOKEN; the token goes to curl on stdin, never on its command line).
#     Ready = unresolved issues of --project and/or subtasks of --epic tagged
#     builder:claude or builder:codex, with no unresolved issue on any link named
#     in YOUTRACK_BLOCKER_LINKS (';'-separated, default "is required for" — the
#     issues A depends on). Base = origin/HEAD. An issue resolved while the list is
#     paged can shift one page boundary: a task may be missed, never one started wrongly.
# Explicit issues override the ready set. A task whose worktree exists is resumed in it.
set -euo pipefail

die() { echo "task-wave: $*" >&2; exit 2; }
dry=0; base=""; issues=(); raw=(); project=""; epic=""; tracker="${TASK_WAVE_TRACKER:-github}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --base) [ $# -ge 2 ] || die "--base needs a branch"; base="$2"; shift 2 ;;
    --tracker) [ $# -ge 2 ] || die "--tracker needs github or youtrack"; tracker="$2"; shift 2 ;;
    --project) [ $# -ge 2 ] || die "--project needs a project key"; project="$2"; shift 2 ;;
    --epic) [ $# -ge 2 ] || die "--epic needs an issue id"; epic="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) raw+=("$1"); shift ;;
  esac
done
case "$tracker" in github|youtrack) ;; *) die "unknown tracker '$tracker' — github or youtrack" ;; esac
yt_id='^[A-Za-z][A-Za-z0-9_]*-[0-9]+$'
if [ "$tracker" = github ]; then
  [ -z "$project$epic" ] || die "--project and --epic are YouTrack options (--tracker youtrack)"
  for a in ${raw[@]+"${raw[@]}"}; do
    [[ "$a" =~ ^#?[0-9]+$ ]] || die "not an issue number: $a"
    issues+=("$((10#${a#\#}))")   # canonical decimal: 02 and #2 are #2, deduplicated below
  done
else
  for a in ${raw[@]+"${raw[@]}"}; do [[ "$a" =~ $yt_id ]] || die "not a YouTrack issue id: $a"; done
  [ -z "$project" ] || [[ "$project" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "not a project key: $project"
  [ -z "$epic" ] || [[ "$epic" =~ $yt_id ]] || die "not a YouTrack issue id: $epic"
fi

if [ "$tracker" = github ]; then
  command -v gh >/dev/null || die "gh is not on PATH"
else
  command -v curl >/dev/null || die "curl is not on PATH"
  command -v jq >/dev/null || die "jq is not on PATH"
fi
[ $dry = 1 ] || command -v tmux >/dev/null || die "tmux is not on PATH (try --dry-run to see the plan)"
root="$(git rev-parse --show-toplevel)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"; name="$(basename "$root")"

# --- YouTrack adapter: configuration, then every read through yt_get, which
# stops the run on anything but a 2xx JSON answer of the expected shape.
if [ "$tracker" = youtrack ]; then
  yt_url="${YOUTRACK_URL:-}"; yt_url="${yt_url%/}"
  [ -n "$yt_url" ] || die "YOUTRACK_URL is not set (the instance root, e.g. https://youtrack.example.com)"
  case "$yt_url" in https://?*) ;; *) die "YOUTRACK_URL must be https:// — the token is sent with every request" ;; esac
  yt_var="${YOUTRACK_TOKEN_VAR:-YOUTRACK_TOKEN}"
  [[ "$yt_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "YOUTRACK_TOKEN_VAR is not a variable name: $yt_var"
  yt_token="${!yt_var:-}"
  [ -n "$yt_token" ] || die "\$$yt_var is empty — export the YouTrack token in it (YOUTRACK_TOKEN_VAR names the variable)"
  [[ "$yt_token" =~ ^[A-Za-z0-9._:+/=-]+$ ]] || die "\$$yt_var holds characters a YouTrack token does not have"
  yt_links="${YOUTRACK_BLOCKER_LINKS:-is required for}"
  [ ${#raw[@]} -gt 0 ] || [ -n "$project$epic" ] || die "name the wave: --project KEY and/or --epic ID (or explicit issue ids)"
fi
yt_uri() { jq -rn --arg s "$1" '$s | @uri'; }
# yt_get <path?query> <jq shape test> — the body, or a stop. The token reaches
# curl on stdin (--config -): never on a command line, in ps or in a log.
yt_get() {
  local body
  body="$(printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/json"\n' "$yt_token" \
    | curl -fsS --max-time 30 --config - "$yt_url$1")" \
    || die "YouTrack did not answer ${1%%\?*} — refusing to guess that it is ready"
  printf '%s' "$body" | jq -e "$2" >/dev/null 2>&1 \
    || die "YouTrack answered ${1%%\?*} with something that is not the expected JSON — is YOUTRACK_URL the instance root? refusing to guess"   # lint: allow — jq's own message is not the point
  printf '%s' "$body"
}
# yt_page <query> <top> <skip> — one page of a search (a JSON array). $top is always
# sent: without it YouTrack silently returns at most 500 issues.
yt_page() { yt_get "/api/issues?query=$(yt_uri "$1")&fields=idReadable,tags(name)&\$top=$2&\$skip=$3" 'type == "array"'; }
# "<id>\t<builder tags>" per issue of a page
yt_tsv='.[] | [.idReadable, ([.tags[]?.name | select(. == "builder:claude" or . == "builder:codex")] | unique | join(" "))] | @tsv'
yt_search() { yt_page "$@" | jq -r "$yt_tsv"; }
# yt_blocked <id> — 0 when some link in YOUTRACK_BLOCKER_LINKS names an unresolved issue.
# It runs as an `if` condition, where set -e is off: a failed read must exit by hand,
# or an unreadable blocker list would read as "no blocker" — ready.
yt_blocked() {
  local rest="$yt_links;" l hit
  while [ -n "$rest" ]; do
    l="${rest%%;*}"; rest="${rest#*;}"; [ -n "$l" ] || continue
    hit="$(yt_search "$l: $1 #Unresolved" 1 0)" || exit 2
    [ -z "$hit" ] || return 0
  done
  return 1
}

# The ready set (and, on YouTrack, each task's builder tags and canonical id).
builders=()
if [ "$tracker" = github ]; then
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || die "gh cannot read this repository"
  [ -n "$base" ] || base="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)" || die "gh cannot read the default branch"
  # every open issue with a builder label (server-side label filter, all pages —
  # no count limit), pull requests excluded, then its blockers
  if [ ${#issues[@]} -eq 0 ]; then
    labelled=""
    for label in builder:claude builder:codex; do
      page="$(gh api --paginate "repos/$repo/issues?state=open&per_page=100&labels=$label" \
        -q '.[] | select(.pull_request == null) | .number')" || die "gh cannot list the issues labelled $label"
      labelled="$labelled $page"
    done
    for n in $(printf '%s\n' $labelled | sort -nu); do
      # every page of blockers (30 per page by default); ready = no open one on any page
      open="$(gh api --paginate "repos/$repo/issues/$n/dependencies/blocked_by?per_page=100" \
        -q '.[] | select(.state == "open") | .number')" \
        || die "cannot read the blockers of #$n — refusing to guess that it is ready"
      [ -z "$open" ] && issues+=("$n")
    done
    [ ${#issues[@]} -gt 0 ] || { echo "task-wave: no ready task in $repo (open, builder:claude|codex label, no open blocker)"; exit 0; }
  fi
else
  if [ -z "$base" ]; then
    base="$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD)" \
      || die "origin/HEAD is not set — pass --base <branch>, or set it: git remote set-head origin --auto"
    base="${base#origin/}"
  fi
  if [ ${#raw[@]} -gt 0 ]; then
    # explicit ids: the server's idReadable is the id (dev-05 is DEV-5); unknown → stop
    for a in "${raw[@]}"; do
      line="$(yt_get "/api/issues/$(yt_uri "$a")?fields=idReadable,tags(name)" 'type == "object" and (.idReadable | type) == "string"' \
        | jq -r '[.idReadable, ([.tags[]?.name | select(. == "builder:claude" or . == "builder:codex")] | unique | join(" "))] | @tsv')"
      issues+=("${line%%	*}"); builders+=("${line#*	}")
    done
  else
    # Every blocker link name must be one of this instance's link names: YouTrack
    # does not refuse an unknown one — it searches the words as text, which finds
    # nothing, and every blocked task would read as ready.
    names="$(yt_get "/api/issueLinkTypes?fields=sourceToTarget,targetToSource&\$top=200" 'type == "array"' \
      | jq -r '.[] | .sourceToTarget, .targetToSource | select(. != null and . != "")')"
    rest="$yt_links;"
    while [ -n "$rest" ]; do
      l="${rest%%;*}"; rest="${rest#*;}"; [ -n "$l" ] || continue
      known=0
      while IFS= read -r t; do [ "$t" = "$l" ] && known=1; done <<EOF
$names
EOF
      [ $known = 1 ] || die "YOUTRACK_BLOCKER_LINKS: '$l' is not a link name on this instance ($(printf '%s' "$names" | tr '\n' ',' | sed 's/,$//')) — refusing to guess"
    done
    q="${project:+project: $project }${epic:+subtask of: $epic }#Unresolved sort by: created asc"
    skip=0; cand=""
    while :; do
      body="$(yt_page "$q" 100 $skip)"
      count="$(printf '%s' "$body" | jq length)"
      page="$(printf '%s' "$body" | jq -r "$yt_tsv")"
      [ -z "$page" ] || cand="$cand$page"$'\n'
      [ "$count" -lt 100 ] && break   # a short page ends the list
      skip=$((skip + 100))
    done
    while IFS='	' read -r id tags; do
      [ -n "$id" ] && [ -n "$tags" ] || continue
      if yt_blocked "$id"; then continue; fi
      issues+=("$id"); builders+=("$tags")
    done <<EOF
$cand
EOF
    [ ${#issues[@]} -gt 0 ] || { echo "task-wave: no ready task in ${project:+project $project }${epic:+epic $epic} (unresolved, builder:claude|codex tag, no unresolved blocker)"; exit 0; }
  fi
fi

# One entry per issue: an issue named twice must not get two agents in one checkout.
uniq_issues=(); uniq_builders=(); seen=" "; i=0
while [ $i -lt ${#issues[@]} ]; do
  n="${issues[$i]}"
  case "$seen" in *" $n "*) i=$((i+1)); continue ;; esac
  seen="$seen$n "; uniq_issues+=("$n"); uniq_builders+=("${builders[$i]-}")
  i=$((i+1))
done
issues=("${uniq_issues[@]}"); builders=("${uniq_builders[@]}")

# Is $1 a worktree of this repository, checked out on branch $2? (canonical paths)
our_worktree() {
  local want; want="$(cd "$1" && pwd -P)"
  git -C "$root" worktree list --porcelain | awk -v w="$want" -v b="refs/heads/$2" '
    $1 == "worktree" { cur = substr($0, 10) }
    $1 == "branch" && cur == w && $2 == b { found = 1 }
    END { exit !found }'
}
# Where is branch $1 checked out, if anywhere? (git refuses a second checkout)
branch_path() {
  git -C "$root" worktree list --porcelain | awk -v b="refs/heads/$1" '
    $1 == "worktree" { cur = substr($0, 10) }
    $1 == "branch" && $2 == b { print cur; exit }'
}

# One launcher per repository at a time: the window check below and the window it
# leads to must not interleave with another run's (two agents in one checkout).
# mkdir is atomic everywhere; the lock sits in the git dir every worktree shares.
common="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ $dry = 0 ]; then
  lock="$common/task-wave.lock"
  if ! mkdir "$lock" 2>/dev/null; then   # lint: allow — a failing mkdir is the answer: the lock is held
    holder="$(cat "$lock/pid" 2>/dev/null)" || holder="?"   # lint: allow — the holder may not have written its pid yet
    die "another task-wave holds $lock (pid $holder) — wait for it; if that process is gone, remove the directory"
  fi
  trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
  echo $$ > "$lock/pid"
fi

# A live window named after a task in this wave's session is that task's agent,
# still running (a window closes when its CLI exits) — never start a second one
# beside it. The session is named by the checkout's basename, so two repositories
# can share the name: it carries its owner (@task_wave_repo = this git common
# dir), and a session owned by another repository — or by nobody — is not ours.
session="wave-$name"; running=" "
if command -v tmux >/dev/null && tmux has-session -t "=$session" 2>/dev/null; then   # lint: allow — "no session" is the answer, not an error
  owner="$(tmux show-options -qv -t "=$session:" @task_wave_repo)"
  [ "$owner" = "$common" ] || die "tmux session $session belongs to ${owner:-another use of that name} — not this repository ($common); rename or close it"
  running=" $(tmux list-windows -t "=$session" -F '#{window_name}' | tr '\n' ' ')"
fi

# Plan every task first; anything that cannot be started safely stops the run
# before a single worktree or window exists.
plan_n=(); plan_wt=(); plan_mode=(); plan_cmd=(); plan_win=(); need_claude=0; need_codex=0
# A tmux server keeps the environment it started with, so a window may not see
# this shell's PATH: run the CLI by the absolute path checked here, with this PATH.
# Both are made absolute against this directory: the window starts in the task's
# worktree, where a relative PATH entry (or "", which means ".") points elsewhere.
here="$(pwd -P)"
abs() { case "$1" in /*) printf '%s' "$1" ;; "") printf '%s' "$here" ;; *) printf '%s/%s' "$here" "$1" ;; esac; }
launch_path=""; rest="$PATH:"
while [ -n "$rest" ]; do d="${rest%%:*}"; rest="${rest#*:}"; launch_path="$launch_path${launch_path:+:}$(abs "$d")"; done
claude_bin=claude; codex_bin=codex
if command -v claude >/dev/null; then claude_bin="$(abs "$(command -v claude)")"; fi
if command -v codex >/dev/null; then codex_bin="$(abs "$(command -v codex)")"; fi
run_with_path="env PATH=$(printf %q "$launch_path")"
i=0
while [ $i -lt ${#issues[@]} ]; do
  n="${issues[$i]}"; i=$((i+1))
  if [ "$tracker" = github ]; then
    label="#$n"
    builder="$(gh issue view "$n" --json labels -q '[.labels[].name | select(. == "builder:claude" or . == "builder:codex")] | unique | join(" ")')" \
      || die "gh cannot read #$n"
  else
    label="$n"; builder="${builders[$((i-1))]}"
  fi
  case "$builder" in
    builder:claude) cmd="$run_with_path $(printf %q "$claude_bin") $(printf %q "/task-flow:task $label")"; need_claude=1 ;;
    builder:codex)  cmd="$run_with_path $(printf %q "$codex_bin") $(printf %q "\$task-flow:task $label")"; need_codex=1 ;;
    "") echo "task-wave: $label has no builder:claude or builder:codex label — skipped"; continue ;;
    *)  echo "task-wave: $label has both builder labels — skipped (keep one)"; continue ;;
  esac
  wt="$(dirname "$root")/$name-$n"; br="task-$n"
  case "$running" in *" $label "*)
    echo "task-wave: $label is already running in tmux window $label of $session — not started again"; continue ;;
  esac
  if [ -e "$wt" ]; then
    our_worktree "$wt" "$br" || die "$wt exists but is not this repository's worktree on $br — move it or start $label by hand"
    mode=resume; how="worktree on $br exists — resuming in it"
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$br"; then
    held="$(branch_path "$br")"
    [ -z "$held" ] || die "$br is checked out at $held, not at $wt — finish $label there or remove that worktree"
    mode=branch; how="git worktree add $wt $br   (branch exists)"
  else
    mode=new; how="git worktree add $wt -b $br origin/$base"
  fi
  printf '%s %s → %s\n    %s\n    tmux window %s: %s\n' "$label" "$builder" "$wt" "$how" "$label" "$cmd"
  plan_n+=("$n"); plan_wt+=("$wt"); plan_mode+=("$mode"); plan_cmd+=("$cmd"); plan_win+=("$label")
done
[ ${#plan_n[@]} -gt 0 ] || exit 0
# A window whose CLI is missing would close at once with "command not found",
# after the worktree exists — check the harnesses this wave needs before anything.
missing=""
[ $need_claude = 1 ] && ! command -v claude >/dev/null && missing="$missing claude"
[ $need_codex = 1 ] && ! command -v codex >/dev/null && missing="$missing codex"
if [ -n "$missing" ]; then
  [ $dry = 1 ] || die "not on PATH:$missing — install it, or relabel those tasks"
  echo "task-wave: not on PATH:$missing — the real run will refuse"
fi
[ $dry = 1 ] && { echo "task-wave: dry run — nothing created"; exit 0; }

git -C "$root" fetch -q origin "$base" || die "cannot fetch origin/$base"
i=0
while [ $i -lt ${#plan_n[@]} ]; do
  n="${plan_n[$i]}"; wt="${plan_wt[$i]}"; cmd="${plan_cmd[$i]}"; win="${plan_win[$i]}"
  case "${plan_mode[$i]}" in
    new)    git -C "$root" worktree add -q "$wt" -b "task-$n" "origin/$base" ;;
    branch) git -C "$root" worktree add -q "$wt" "task-$n" ;;
  esac
  if tmux has-session -t "=$session" 2>/dev/null; then   # lint: allow — "no session" is the answer, not an error
    tmux new-window -t "=$session" -n "$win" -c "$wt" "$cmd"
  else
    # one tmux call: the owner is set before a window that exits at once could take the session with it
    tmux new-session -d -s "$session" -n "$win" -c "$wt" "$cmd" \; set-option -t "=$session:" @task_wave_repo "$common"
  fi
  i=$((i+1))
done
echo "task-wave: ${#plan_n[@]} session(s) in tmux — attach with: tmux attach -t $session"
