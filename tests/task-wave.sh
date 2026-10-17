#!/usr/bin/env bash
# tests/task-wave.sh — negative controls for templates/wave/task-wave.sh with a
# stub `gh` (fixture JSON through the script's own jq filters, GitHub's 100-item
# pages unless --paginate), a `git` wrapper that counts fetches, stub `claude` /
# `codex` that record their argv and cwd, and a private tmux server. No network,
# no model.
set -uo pipefail   # no -e: cases assert non-zero exits themselves
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TW="$ROOT/templates/wave/task-wave.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
export TMUX_TMPDIR="$TMP/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
trap 'tmux kill-server >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }
check() { if eval "$2"; then ok; else bad "$1"; fi; }
for t in jq tmux; do command -v $t >/dev/null || { echo "tests/task-wave.sh: $t is required" >&2; exit 1; }; done
REAL_GIT="$(command -v git)"

# --- fixtures. Open issues, newest first as GitHub lists them:
#   #2 claude, blocker closed (ready) · #3 codex, blocker open · #4 epic, no builder label
#   #5 codex, no blockers (ready) · #7 a pull request labelled builder:claude (never a task)
#   #1000..#1149 claude, each blocked by an open issue — so the ready #350 sits past
#   item 100 of the labelled list and past item 200 of all open issues.
#   #360 claude: 105 closed blockers, then an open one — on the blockers' second page.
#   #370 codex: 120 closed blockers, all on two pages — ready.
F="$TMP/fx"; mkdir -p "$F"
jq -n '
  [range(1000;1150) | {number: ., labels: [{name: "builder:claude"}]}]
  + [range(400;460) | {number: ., labels: [{name: "bug"}]}]
  + [{number: 380, labels: [{name: "builder:claude"}, {name: "builder:codex"}]},
     {number: 370, labels: [{name: "builder:codex"}]},
     {number: 360, labels: [{name: "builder:claude"}]},
     {number: 350, labels: [{name: "builder:claude"}]},
     {number: 7, labels: [{name: "builder:claude"}], pull_request: {url: "x"}},
     {number: 5, labels: [{name: "bug"}, {name: "builder:codex"}]},
     {number: 4, labels: [{name: "epic"}]},
     {number: 3, labels: [{name: "builder:codex"}]},
     {number: 2, labels: [{name: "builder:claude"}]}]' > "$F/open.json"
echo '[{"number":1,"state":"closed"}]' > "$F/blocked-2.json"
echo '[{"number":2,"state":"open"}]'   > "$F/blocked-3.json"
echo '[]' > "$F/blocked-5.json"; echo '[]' > "$F/blocked-350.json"
jq -n '[range(0;105) | {number: (2000 + .), state: "closed"}] + [{number: 2105, state: "open"}]' > "$F/blocked-360.json"
jq -n '[range(0;120) | {number: (3000 + .), state: "closed"}]' > "$F/blocked-370.json"
for n in $(seq 1000 1149); do echo '[{"number":9,"state":"open"}]' > "$F/blocked-$n.json"; done
echo '[]' > "$F/blocked-380.json"
for n in 2 3 4 5 350 360 370 380; do jq "{labels: (.[] | select(.number == $n) | .labels)}" "$F/open.json" > "$F/issue-$n.json"; done
echo '{"nameWithOwner":"o/lab","defaultBranchRef":{"name":"main"}}' > "$F/repo.json"

mkdir -p "$TMP/bin" "$TMP/log"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
# fixtures through the caller's -q filter, as gh does; one 100-item page unless --paginate
q=""; prev=""; pag=0; args=()
for a in "$@"; do
  [ "$prev" = "-q" ] && q="$a"
  if [ "$a" = "--paginate" ]; then pag=1; else args+=("$a"); fi
  prev="$a"
done
set -- "${args[@]}"
[ -n "${GH_FAIL:-}" ] && case "$*" in *"$GH_FAIL"*) echo "gh: simulated failure" >&2; exit 1 ;; esac
case "$1 $2" in
  "repo view")  jq -r "$q" "$FX/repo.json"; exit ;;
  "issue view") [ -n "${GH_SLOW:-}" ] && sleep "$GH_SLOW"
                [ -f "$FX/issue-$3.json" ] || exit 4; jq -r "$q" "$FX/issue-$3.json"; exit ;;
  "issue list") jq -r '.[:200]' "$FX/open.json" | jq -r "$q"; exit ;;     # gh's --limit 200 truncation
esac
[ "$1" = api ] || { echo "gh stub: unexpected: $*" >&2; exit 3; }
case "$2" in
  repos/o/lab/issues\?*)
    label="${2##*labels=}"; label="${label%%&*}"
    sel="$(jq --arg l "$label" '[.[] | select(any(.labels[]; .name == $l))]' "$FX/open.json")"
    [ $pag = 1 ] || sel="$(printf '%s' "$sel" | jq '.[:100]')"
    printf '%s' "$sel" | jq -r "$q" ;;
  repos/o/lab/issues/*/dependencies/blocked_by*)
    n="${2#repos/o/lab/issues/}"; n="${n%%/*}"
    [ -f "$FX/blocked-$n.json" ] || { echo "gh stub: no blockers fixture for #$n" >&2; exit 4; }
    # GitHub pages: per_page from the query (default 30); without --paginate only page 1
    per=30; case "$2" in *per_page=*) per="${2##*per_page=}"; per="${per%%&*}" ;; esac
    total="$(jq length "$FX/blocked-$n.json")"; pages=$(( (total + per - 1) / per )); [ $pages -ge 1 ] || pages=1
    [ $pag = 1 ] || pages=1
    p=0; while [ $p -lt $pages ]; do
      [ $p -ge 1 ] && [ "${GH_FAIL_PAGE2:-}" = "$n" ] && { echo "gh: simulated failure on page 2" >&2; exit 1; }
      jq -r --argjson a $((p * per)) --argjson b $(((p + 1) * per)) ".[\$a:\$b] | $q" "$FX/blocked-$n.json"
      p=$((p+1))
    done ;;
  *) echo "gh stub: unexpected api: $2" >&2; exit 3 ;;
esac
EOF
printf '#!/usr/bin/env bash\ncase " $* " in *" fetch "*) echo fetch >> "$STUB_LOG/fetches" ;; esac\nexec %q "$@"\n' "$REAL_GIT" > "$TMP/bin/git"
# the stub CLIs' interpreter lives only in $TMP/bin, as node lives in nvm's bin for
# the real ones (`#!/usr/bin/env node`): a window without the launcher's PATH cannot run them
for a in claude codex; do
  printf '#!/usr/bin/env tw-interp\nprintf "%%s\\n" "$PWD" "$@" > "$STUB_LOG/%s-$(basename "$PWD")"; echo x >> "$STUB_LOG/launches-%s-$(basename "$PWD")"; sleep 60\n' "$a" "$a" > "$TMP/bin/$a"
done
chmod +x "$TMP/bin/"*
ln -s "$(command -v bash)" "$TMP/bin/tw-interp"
export PATH="$TMP/bin:$PATH" FX="$F" STUB_LOG="$TMP/log"
fetches() { if [ -f "$STUB_LOG/fetches" ]; then wc -l < "$STUB_LOG/fetches" | tr -d ' '; else echo 0; fi; }
# settle FILE N — the stub CLIs write from inside tmux, after the launcher returned:
# wait (bounded, 4 s) until FILE has N launches, then 0.5 s more so an extra launch
# would show, and print the count.
settle() {
  local c=0 i
  for i in $(seq 1 20); do
    c=0; [ -f "$1" ] && c="$(wc -l < "$1" | tr -d ' ')"
    [ "$c" -ge "$2" ] && break; sleep 0.2
  done
  sleep 0.5; c=0; [ -f "$1" ] && c="$(wc -l < "$1" | tr -d ' ')"
  echo "$c"
}

# --- a repository with an origin: main, and develop one commit ahead
git init -q --bare -b main "$TMP/origin.git"
git init -q -b main "$TMP/w/lab"; cd "$TMP/w/lab"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git remote add origin "$TMP/origin.git"; git push -q origin main
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m develop-only
git push -q origin HEAD:develop; git reset -q --hard origin/main
git fetch -q origin; rm -f "$STUB_LOG/fetches"
DEVELOP_SHA="$(git rev-parse origin/develop)"; MAIN_SHA="$(git rev-parse origin/main)"

# 1. dry run on the ready set: #2, #5 and #350 (past the first page), nothing created or fetched
out="$(bash "$TW" --dry-run)"; rc=$?
check "dry run exits 0" '[ $rc -eq 0 ]'
check "ready set is exactly #2, #5, #350, #370 (#360's open blocker is on page 2)" '[ "$(printf "%s\n" "$out" | sed -n "s/^#\([0-9]*\) builder.*/\1/p" | tr "\n" " ")" = "2 5 350 370 " ]'
check "a pull request with a builder label is not a task" '! printf "%s" "$out" | grep -q "^#7 "'
check "claude gets /task-flow:task #2" 'printf "%s" "$out" | grep -qF "claude /task-flow:task\\ #2"'
check "codex gets \$task-flow:task #5, the \$ escaped for the shell" 'printf "%s" "$out" | grep -qF "codex \\\$task-flow:task\\ #5"'
check "dry run: no worktree, no tmux session, no fetch" '[ "$(git worktree list | wc -l)" -eq 1 ] && ! tmux has-session -t =wave-lab 2>/dev/null && [ "$(fetches)" = 0 ]'

# 2. an explicit issue without a builder label is skipped; a non-number is refused
out="$(bash "$TW" --dry-run 4)"
check "#380 with both builder labels is not in the ready set" '! printf "%s" "$(bash "$TW" --dry-run)" | grep -q "^#380 "'
out="$(bash "$TW" --dry-run 380)"
check "explicit #380 with both builder labels → skipped, not guessed" 'printf "%s" "$out" | grep -q "#380 has both builder labels"'
out="$(bash "$TW" --dry-run 4)"
check "explicit #4 without builder label → skipped" 'printf "%s" "$out" | grep -q "#4 has no builder"'
bash "$TW" --dry-run abc >/dev/null 2>&1; rc=$?
check "a non-number argument → rc 2" '[ $rc -eq 2 ]'

# 3. every tracker read that fails stops the run (rc 2) instead of reading as "none" or "ready"
for f in "labels=builder:claude" "labels=builder:codex" "issues/350/dependencies/blocked_by" "issue view 5"; do
  GH_FAIL="$f" bash "$TW" --dry-run >/dev/null 2>"$TMP/err"; rc=$?
  check "gh failure on '$f' → rc 2" '[ $rc -eq 2 ] && grep -q "task-wave:" "$TMP/err"'
done

GH_FAIL_PAGE2=370 bash "$TW" --dry-run >/dev/null 2>"$TMP/err"; rc=$?
check "blockers page 2 of #370 fails after page 1 printed → rc 2, not ready" '[ $rc -eq 2 ] && grep -q "blockers of #370" "$TMP/err"'

# 4. no tmux (not a dry run) → refused before anything is created
mkdir -p "$TMP/notmux"
for c in gh jq dirname basename bash awk sort seq sed tr wc; do ln -sf "$(command -v $c)" "$TMP/notmux/$c"; done
ln -sf "$TMP/bin/git" "$TMP/notmux/git"
PATH="$TMP/notmux" "$TMP/notmux/bash" "$TW" 2 >/dev/null 2>"$TMP/err"; rc=$?
check "no tmux → rc 2, no worktree, no fetch" '[ $rc -eq 2 ] && grep -q "tmux is not on PATH" "$TMP/err" && [ "$(git worktree list | wc -l)" -eq 1 ] && [ "$(fetches)" = 0 ]'

# 4b. a wave that needs a harness not on PATH → refused before fetch, worktree or window
mkdir -p "$TMP/nocodex"
for c in gh jq dirname basename bash awk sort seq sed tr wc tmux mkdir rmdir rm cat; do ln -sf "$(command -v $c)" "$TMP/nocodex/$c"; done
ln -sf "$TMP/bin/git" "$TMP/nocodex/git"; ln -sf "$TMP/bin/claude" "$TMP/nocodex/claude"; ln -sf "$TMP/bin/tw-interp" "$TMP/nocodex/tw-interp"
PATH="$TMP/nocodex" "$TMP/nocodex/bash" "$TW" 2 5 >/dev/null 2>"$TMP/err"; rc=$?
check "codex missing for #5 → rc 2, #2 not started, no fetch" '[ $rc -eq 2 ] && grep -q "not on PATH: codex" "$TMP/err" && [ ! -e "$TMP/w/lab-2" ] && ! tmux has-session -t =wave-lab 2>/dev/null && [ "$(fetches)" = 0 ]'
out="$(PATH="$TMP/nocodex" "$TMP/nocodex/bash" "$TW" --dry-run 2 5)"; rc=$?
check "dry run names the missing harness and still exits 0" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "the real run will refuse"'
PATH="$TMP/nocodex" "$TMP/nocodex/bash" "$TW" 2 >/dev/null 2>&1; rc=$?
check "a wave needing only claude starts without codex installed" '[ $rc -eq 0 ] && [ -d "$TMP/w/lab-2" ]'
tmux kill-server >/dev/null 2>&1 || true; git worktree remove --force "$TMP/w/lab-2"; git branch -q -D task-2; rm -f "$STUB_LOG/fetches" "$STUB_LOG/claude-lab-2" "$STUB_LOG/launches-claude-lab-2"

# 5. a directory at a task's worktree path that is not this repo's worktree on task-<N> → refused, nothing started
mkdir -p "$TMP/w/lab-5"
bash "$TW" 2 5 >/dev/null 2>"$TMP/err"; rc=$?
check "plain directory at lab-5 → rc 2, #2 not started either" '[ $rc -eq 2 ] && grep -q "not this repository.s worktree" "$TMP/err" && [ ! -e "$TMP/w/lab-2" ] && ! tmux has-session -t =wave-lab 2>/dev/null'
rmdir "$TMP/w/lab-5"
git worktree add -q "$TMP/w/lab-5" -b other origin/main
bash "$TW" 5 >/dev/null 2>"$TMP/err"; rc=$?
check "our worktree on another branch at lab-5 → rc 2" '[ $rc -eq 2 ] && grep -q "on task-5" "$TMP/err"'
git worktree remove --force "$TMP/w/lab-5"; git branch -q -D other

# 5b. task-5 already checked out in another worktree (not at lab-5) → refused in the plan, nothing started
git worktree add -q "$TMP/w/elsewhere" -b task-5 origin/main
bash "$TW" 2 5 >/dev/null 2>"$TMP/err"; rc=$?
check "task-5 held by another worktree → rc 2, #2 not started, no fetch" '[ $rc -eq 2 ] && grep -q "task-5 is checked out at" "$TMP/err" && [ ! -e "$TMP/w/lab-2" ] && ! tmux has-session -t =wave-lab 2>/dev/null && [ "$(fetches)" = 0 ]'
git worktree remove --force "$TMP/w/elsewhere"; git branch -q -D task-5

# 5c. a number named twice — also as #2 or 02 — → one plan entry, one window, one launch
bash "$TW" 2 2 02 >/dev/null 2>&1; rc=$?; n="$(settle "$STUB_LOG/launches-claude-lab-2" 1)"
check "'2 2 02' on a new worktree → one window, one claude launch" '[ $rc -eq 0 ] && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 1 ] && [ "$n" -eq 1 ] && [ ! -e "$TMP/w/lab-02" ]'
tmux kill-server >/dev/null 2>&1 || true
bash "$TW" 2 '#2' 002 >/dev/null 2>&1; rc=$?; n="$(settle "$STUB_LOG/launches-claude-lab-2" 2)"
check "'2 #2 002' on the existing worktree → one window, one more launch" '[ $rc -eq 0 ] && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 1 ] && [ "$n" -eq 2 ]'
tmux kill-server >/dev/null 2>&1 || true; git worktree remove --force "$TMP/w/lab-2"; git branch -q -D task-2
rm -f "$STUB_LOG/fetches" "$STUB_LOG/claude-lab-2" "$STUB_LOG/launches-claude-lab-2"

# 6. the real run: one worktree per task from origin/main, one tmux window each, the right CLI and prompt
bash "$TW" 2 5 > "$TMP/run.out"; rc=$?
check "run exits 0, one fetch, names the session" '[ $rc -eq 0 ] && [ "$(fetches)" = 1 ] && grep -q "tmux attach -t wave-lab" "$TMP/run.out"'
check "worktrees lab-2 / lab-5 on task-2 / task-5 at origin/main" '[ "$(git -C "$TMP/w/lab-2" branch --show-current)" = task-2 ] && [ "$(git -C "$TMP/w/lab-5" branch --show-current)" = task-5 ] && [ "$(git -C "$TMP/w/lab-2" rev-parse HEAD)" = "$MAIN_SHA" ]'
check "windows #2 and #5 in session wave-lab" '[ "$(tmux list-windows -t =wave-lab -F "#{window_name}" | sort | tr "\n" " ")" = "#2 #5 " ]'
for i in $(seq 1 20); do [ -s "$STUB_LOG/claude-lab-2" ] && [ -s "$STUB_LOG/codex-lab-5" ] && break; sleep 0.3; done
check "claude ran in lab-2 with /task-flow:task #2" '[ "$(sed -n 1p "$STUB_LOG/claude-lab-2")" = "$TMP/w/lab-2" ] && [ "$(sed -n 2p "$STUB_LOG/claude-lab-2")" = "/task-flow:task #2" ]'
check "codex ran in lab-5 with \$task-flow:task #5" '[ "$(sed -n 1p "$STUB_LOG/codex-lab-5")" = "$TMP/w/lab-5" ] && [ "$(sed -n 2p "$STUB_LOG/codex-lab-5")" = "\$task-flow:task #5" ]'

# 7. a second run while #2's agent is still running: no second agent in the same checkout
out="$(bash "$TW" 2)"; rc=$?
check "#2 already running → not started again" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "#2 is already running"'
out="$(bash "$TW" 02)"; rc=$?
check "02 is #2, already running → not started again" '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "#2 is already running"'
n="$(settle "$STUB_LOG/launches-claude-lab-2" 1)"
check "still two windows and one claude launch in lab-2" '[ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 2 ] && [ "$n" -eq 1 ]'
# … and once that window is gone (the agent exited), the same worktree is resumed in a new one
tmux kill-window -t "=wave-lab:#2"
out="$(bash "$TW" 2)"
check "window gone → existing worktree resumed in a new window" 'printf "%s" "$out" | grep -q "exists — resuming" && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 2 ]'
check "the session carries its owner, this repository's git common dir" '[ "$(tmux show-options -qv -t =wave-lab: @task_wave_repo)" = "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]'

# 7a. another checkout with the same basename (…/other/lab) while this wave-lab runs #2:
#     its own #2 is not "already running" — the session is not its own; refused before anything
git clone -q "$TMP/origin.git" "$TMP/other/lab"; f0="$(fetches)"
(cd "$TMP/other/lab" && bash "$TW" 2 >/dev/null 2>"$TMP/err"); rc=$?
check "same basename, other repository → rc 2, not a silent skip, nothing created" '[ $rc -eq 2 ] && grep -q "tmux session wave-lab belongs to" "$TMP/err" && [ ! -e "$TMP/other/lab-2" ] && [ "$(fetches)" = "$f0" ]'
#     … and a wave-<name> session nobody marked (made by hand) is not read either
git clone -q "$TMP/origin.git" "$TMP/s/solo"; tmux new-session -d -s wave-solo "sleep 60"
(cd "$TMP/s/solo" && bash "$TW" 2 >/dev/null 2>"$TMP/err"); rc=$?
check "an unmarked wave-solo session → rc 2" '[ $rc -eq 2 ] && grep -q "belongs to another use of that name" "$TMP/err" && [ ! -e "$TMP/s/solo-2" ]'

# 7b. two launchers at once on a resumable task: one starts it, the other is refused — never two agents
tmux kill-window -t "=wave-lab:#2"; rm -f "$STUB_LOG/launches-claude-lab-2"
GH_SLOW=1 bash "$TW" 2 >"$TMP/a.out" 2>"$TMP/a.err" & pa=$!
sleep 0.3
GH_SLOW=1 bash "$TW" 2 >"$TMP/b.out" 2>"$TMP/b.err"; rb=$?
wait $pa; ra=$?
n="$(settle "$STUB_LOG/launches-claude-lab-2" 1)"
check "concurrent run: first starts #2, second refused by the lock" '[ $ra -eq 0 ] && [ $rb -eq 2 ] && grep -q "another task-wave holds" "$TMP/b.err"'
check "concurrent run: one window #2, one launch" '[ "$(tmux list-windows -t =wave-lab -F "#{window_name}" | grep -cx "#2")" -eq 1 ] && [ "$n" -eq 1 ]'
check "the lock is released after a run" '[ ! -e "$(git rev-parse --git-common-dir)/task-wave.lock" ]'

# 8. a branch left behind by a removed worktree is reused, not re-created from base
tmux kill-server >/dev/null 2>&1 || true
git worktree remove --force "$TMP/w/lab-5"
out="$(bash "$TW" 5)"
check "branch task-5 without worktree → reused" 'printf "%s" "$out" | grep -q "(branch exists)" && [ "$(git -C "$TMP/w/lab-5" branch --show-current)" = task-5 ]'

# 9. --base starts a new task's worktree at origin/<base>, really
tmux kill-server >/dev/null 2>&1 || true
out="$(bash "$TW" --base develop 350)"; rc=$?
check "--base develop: worktree lab-350 at origin/develop, not main" '[ $rc -eq 0 ] && [ "$(git -C "$TMP/w/lab-350" rev-parse HEAD)" = "$DEVELOP_SHA" ] && [ "$DEVELOP_SHA" != "$MAIN_SHA" ]'

# 10. the window's environment is not the launcher's. tmux 3.4 hands a new window the
#     creating client's PATH (measured), but a window can get another one (other tmux
#     versions, update-environment, default-command). A tmux shim that runs the real
#     client with PATH=/usr/bin:/bin models that; the window must still run the CLI the
#     launcher checked — by absolute path, with the launcher's PATH.
tmux kill-server >/dev/null 2>&1 || true
mkdir -p "$TMP/tmuxshim"; REAL_TMUX="$(command -v tmux)"
printf '#!/bin/sh\nexec env PATH=/usr/bin:/bin %s "$@"\n' "$REAL_TMUX" > "$TMP/tmuxshim/tmux"; chmod +x "$TMP/tmuxshim/tmux"
rm -f "$STUB_LOG/launches-claude-lab-2"
PATH="$TMP/tmuxshim:$PATH" bash "$TW" 2 >/dev/null 2>&1; rc=$?
for i in $(seq 1 20); do [ -s "$STUB_LOG/launches-claude-lab-2" ] && break; sleep 0.2; done
check "window with a stripped PATH still runs the checked claude" '[ $rc -eq 0 ] && [ -s "$STUB_LOG/launches-claude-lab-2" ]'

# 11. a relative PATH entry (`relbin`, resolved from the repo root where the launcher
#     runs) holds the CLI and its interpreter; the window starts in ../lab-2, where
#     `relbin` does not exist — the launcher must have made both absolute.
tmux kill-server >/dev/null 2>&1 || true
mkdir -p "$TMP/w/lab/relbin"
printf '#!/usr/bin/env tw-rel-interp\necho x >> "$STUB_LOG/launches-relclaude-$(basename "$PWD")"; sleep 60\n' > "$TMP/w/lab/relbin/claude"
chmod +x "$TMP/w/lab/relbin/claude"; ln -s "$(command -v bash)" "$TMP/w/lab/relbin/tw-rel-interp"
PATH="relbin:$PATH" bash "$TW" 2 >/dev/null 2>&1; rc=$?
for i in $(seq 1 20); do [ -s "$STUB_LOG/launches-relclaude-lab-2" ] && break; sleep 0.2; done
check "CLI and interpreter on a relative PATH entry still start in the worktree" '[ $rc -eq 0 ] && [ -s "$STUB_LOG/launches-relclaude-lab-2" ]'

# ===================== YouTrack (--tracker youtrack) =====================
# A stub curl serves a YouTrack fixture db with the behaviour measured on a live
# instance (1.14.0 spec): no $top → silently at most 500 items; a tag in a query →
# 400 (the tag may not exist yet); a blocker query on an unknown id → 400; GET of an
# unknown id → 404; ids are canonical (dev-05 → DEV-5). It reads the --config from
# stdin like curl and records argv — the token must never be there.
tmux kill-server >/dev/null 2>&1 || true
#   DEV-1 epic · DEV-2 claude, blocker DEV-90 resolved (ready) · DEV-3 codex, blocked by
#   open DEV-2 · DEV-4 no builder tag · DEV-5 codex (ready) · DEV-6 both tags · DEV-7
#   claude, other epic (ready) · DEV-1000..1599 bugs · DEV-350 claude past item 600
#   (ready) · DEV-370 codex, open only as a `blocks` link · OPS-1 claude, other project
jq -n '
  [ {id: "DEV-1", tags: []}, {id: "DEV-90", tags: [], resolved: true},
    {id: "DEV-2", parent: "DEV-1", tags: ["builder:claude"], blockers: ["DEV-90"]},
    {id: "DEV-3", parent: "DEV-1", tags: ["builder:codex"], blockers: ["DEV-2"]},
    {id: "DEV-4", parent: "DEV-1", tags: ["bug"]},
    {id: "DEV-5", parent: "DEV-1", tags: ["builder:codex", "bug"]},
    {id: "DEV-6", parent: "DEV-1", tags: ["builder:claude", "builder:codex"]},
    {id: "DEV-7", parent: "DEV-50", tags: ["builder:claude"]},
    {id: "OPS-1", project: "OPS", tags: ["builder:claude"]} ]
  + [range(1000; 1600) | {id: "DEV-\(.)", tags: ["bug"]}]
  + [ {id: "DEV-350", tags: ["builder:claude"]},
      {id: "DEV-370", tags: ["builder:codex"], blocks: ["DEV-1000"]} ]
  | map({project: "DEV", resolved: false} + .)' > "$F/yt.json"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
cfg="$(cat)"; printf '%s\n' "$*" >> "$STUB_LOG/curl-argv"
err() { echo "curl: (22) The requested URL returned error: $1" >&2; exit 22; }
url=""; for a in "$@"; do case "$a" in https://*|http://*) url="$a" ;; esac; done
case "$cfg" in *"Authorization: Bearer $YT_EXPECT_TOKEN\""*) ;; *) err 401 ;; esac
rest="${url#https://yt.test}"; [ "$rest" != "$url" ] || err 404
path="${rest%%\?*}"; qs=""; case "$rest" in *\?*) qs="${rest#*\?}" ;; esac
dec() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }
query=""; top=""; skip=0
IFS='&'; for kv in $qs; do
  k="$(dec "${kv%%=*}")"; v="${kv#*=}"
  case "$k" in query) query="$(dec "$v")" ;; '$top') top="$v" ;; '$skip') skip="$v" ;; esac
done; unset IFS
[ -n "${YT_FAIL:-}" ] && case "$path $query" in *"$YT_FAIL"*) err 500 ;; esac
[ -n "${YT_HTML:-}" ] && { echo '<!doctype html><html><body>YouTrack</body></html>'; exit 0; }
canon() { jq -rn --arg i "$1" '$i | ascii_upcase | capture("^(?<k>[A-Z][A-Z0-9_]*)-0*(?<n>[0-9]+)$") | "\(.k)-\(.n)"'; }
case "$path" in
  /api/issueLinkTypes)
    if [ -n "${YT_NO_BLOCKS:-}" ]; then echo '[{"sourceToTarget":"is required for","targetToSource":"depends on"}]'
    else echo '[{"sourceToTarget":"relates to","targetToSource":""},{"sourceToTarget":"is required for","targetToSource":"depends on"},{"sourceToTarget":"blocks","targetToSource":"blocked by"}]'; fi ;;
  /api/issues/*)
    id="$(canon "${path#/api/issues/}")" || err 404
    out="$(jq --arg i "$id" '.[] | select(.id == $i) | {idReadable: .id, resolved: (if .resolved then 1 else null end), tags: [.tags[] | {name: .}]}' "$YT_DB")"
    [ -n "$out" ] || err 404; printf '%s\n' "$out" ;;
  /api/issues)
    [ -n "$top" ] || top="${YT_DEFAULT_TOP:-500}"              # the silent cap (500 measured; other builds differ)
    case "$query" in *tag:*) err 400 ;; esac
    re_list='^(project: ([^ ]+) )?(subtask of: ([^ ]+) )?#Unresolved sort by: created asc$'
    re_block='^(is required for|blocks): ([^ ]+) #Unresolved$'
    re_other='^[a-z][a-z ]*: [^ ]+ #Unresolved$'            # an unknown link name: YouTrack searches it as text
    if [ -n "${YT_NO_BLOCKS:-}" ] && [[ $query == blocks:* ]]; then echo '[]'; exit 0; fi
    if [[ $query =~ $re_list ]]; then
      sel="$(jq --arg p "${BASH_REMATCH[2]}" --arg e "${BASH_REMATCH[4]}" \
        '[.[] | select(.resolved | not) | select($p == "" or .project == $p) | select($e == "" or .parent == $e)]' "$YT_DB")"
    elif [[ $query =~ $re_block ]]; then
      field=blockers; [ "${BASH_REMATCH[1]}" = blocks ] && field=blocks; id="${BASH_REMATCH[2]}"
      jq -e --arg i "$id" 'any(.[]; .id == $i)' "$YT_DB" >/dev/null || err 400
      sel="$(jq --arg i "$id" --arg f "$field" '. as $db | [(.[] | select(.id == $i) | .[$f] // [])[] as $b | $db[] | select(.id == $b and (.resolved | not))]' "$YT_DB")"
    elif [[ $query =~ $re_other ]]; then sel='[]'                   # measured: no 400, a text search that finds nothing
    else err 400; fi
    [ -n "${YT_FAIL_PAGE2:-}" ] && [ "$skip" -ge 100 ] && case "$query" in *"$YT_FAIL_PAGE2"*) err 502 ;; esac
    printf '%s' "$sel" | jq --argjson s "$skip" --argjson t "$top" '[.[$s:($s + $t)][] | {idReadable: .id, tags: [.tags[] | {name: .}]}]' ;;
  *) err 404 ;;
esac
EOF
chmod +x "$TMP/bin/curl"
export YOUTRACK_URL=https://yt.test YOUTRACK_TOKEN_VAR=YT_TOK YT_TOK='perm:dGVzdA==.NDQtMQ==.AbC123' YT_DB="$F/yt.json"
export YT_EXPECT_TOKEN="$YT_TOK"
yt() { bash "$TW" --tracker youtrack "$@"; }
ytids() { printf '%s\n' "$1" | sed -n 's/^\([A-Z][A-Z0-9_]*-[0-9]*\) builder.*/\1/p' | tr '\n' ' '; }
git remote set-head origin -d >/dev/null 2>&1 || true   # origin/HEAD unset, as in a repo made with `remote add`
WT0="$(git worktree list | wc -l)"; rm -f "$STUB_LOG/fetches"

# Y1. no origin/HEAD and no --base → refused, naming the way out
yt --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: origin/HEAD unset, no --base → rc 2 naming --base" '[ $rc -eq 2 ] && grep -q -- "--base" "$TMP/err" && grep -q "set-head" "$TMP/err"'
git remote set-head origin main >/dev/null

# Y2. the epic's ready set: DEV-2 and DEV-5 — not DEV-3 (open blocker), DEV-4 (no tag), DEV-7 (other epic)
out="$(yt --dry-run --epic DEV-1)"; rc=$?
check "youtrack --epic DEV-1: ready set exactly DEV-2 DEV-5" '[ $rc -eq 0 ] && [ "$(ytids "$out")" = "DEV-2 DEV-5 " ]'
check "youtrack: both builder tags → skipped with a message" 'printf "%s" "$out" | grep -q "DEV-6 has both builder"'
check "youtrack: claude gets /task-flow:task DEV-2" 'printf "%s" "$out" | grep -qF "claude /task-flow:task\\ DEV-2"'
check "youtrack: codex gets \$task-flow:task DEV-5" 'printf "%s" "$out" | grep -qF "codex \\\$task-flow:task\\ DEV-5"'
check "youtrack: worktree lab-DEV-2 on task-DEV-2" 'printf "%s" "$out" | grep -qF "lab-DEV-2 -b task-DEV-2 origin/main"'
check "youtrack dry run: no worktree, no session, no fetch" '[ "$(git worktree list | wc -l)" -eq "$WT0" ] && ! tmux has-session -t =wave-lab 2>/dev/null && [ "$(fetches)" = 0 ]'

# Y3. --project pages past the silent 500 cap: DEV-350 is item ~610
out="$(yt --dry-run --project DEV)"; rc=$?
check "youtrack --project DEV: DEV-2 DEV-5 DEV-7 DEV-350 DEV-370 (past item 500)" '[ $rc -eq 0 ] && [ "$(ytids "$out")" = "DEV-2 DEV-5 DEV-7 DEV-350 DEV-370 " ]'
out="$(YT_DEFAULT_TOP=42 yt --dry-run --project DEV)"
check "youtrack: a server whose default page is 42, not 500 — same ready set (\$top is always sent)" '[ "$(ytids "$out")" = "DEV-2 DEV-5 DEV-7 DEV-350 DEV-370 " ]'
out="$(yt --dry-run --project DEV --epic DEV-1)"
check "youtrack --project + --epic: both apply" '[ "$(ytids "$out")" = "DEV-2 DEV-5 " ]'
yt --dry-run >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack without --project or --epic → rc 2" '[ $rc -eq 2 ] && grep -q -- "--project" "$TMP/err"'

# Y4. blocker link names come from YOUTRACK_BLOCKER_LINKS; an unknown name is a stop
out="$(YOUTRACK_BLOCKER_LINKS='is required for;blocks' yt --dry-run --project DEV)"; rc=$?
check "youtrack: with 'blocks' as a blocker link DEV-370 is not ready" '[ $rc -eq 0 ] && [ "$(ytids "$out")" = "DEV-2 DEV-5 DEV-7 DEV-350 " ]'
YOUTRACK_BLOCKER_LINKS='precedes' yt --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: a link name the instance does not have → rc 2, not a text search that finds no blocker" '[ $rc -eq 2 ] && grep -q "not a link name on this instance" "$TMP/err"'
YT_NO_BLOCKS=1 YOUTRACK_BLOCKER_LINKS='is required for;blocks' yt --dry-run --project DEV >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: 'blocks' on an instance without a Blocks link type → rc 2" '[ $rc -eq 2 ] && grep -q "blocks" "$TMP/err"'
YT_FAIL=issueLinkTypes yt --dry-run --epic DEV-1 >/dev/null 2>&1; rc=$?
check "youtrack: link types unreadable → rc 2" '[ $rc -eq 2 ]'

# Y5. configuration refusals happen before any request
for c in "YOUTRACK_URL=" "YOUTRACK_URL=http://yt.test" "YOUTRACK_TOKEN_VAR=NO_SUCH_VAR" "YOUTRACK_TOKEN_VAR=bad-name" "YT_TOK=a\"b" "YT_TOK=a b"; do
  rm -f "$STUB_LOG/curl-argv"
  env "$c" bash "$TW" --tracker youtrack --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
  check "youtrack: $c → rc 2 before any request" '[ $rc -eq 2 ] && [ ! -s "$STUB_LOG/curl-argv" ] && grep -q "task-wave:" "$TMP/err"'
done
YOUTRACK_TOKEN_VAR=NO_SUCH_VAR bash "$TW" --tracker youtrack --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"
check "youtrack: an unset token variable is named as empty" 'grep -q "NO_SUCH_VAR is empty" "$TMP/err"'
TASK_WAVE_TRACKER=jira bash "$TW" --dry-run >/dev/null 2>&1; rc=$?
check "an unknown tracker → rc 2" '[ $rc -eq 2 ]'
out="$(TASK_WAVE_TRACKER=youtrack bash "$TW" --dry-run --epic DEV-1)"
check "TASK_WAVE_TRACKER=youtrack selects the adapter" '[ "$(ytids "$out")" = "DEV-2 DEV-5 " ]'
bash "$TW" --dry-run --epic DEV-1 >/dev/null 2>&1; rc=$?
check "--epic is refused on the github tracker" '[ $rc -eq 2 ]'

# Y6. the token never reaches argv; it travels in the --config on stdin
rm -f "$STUB_LOG/curl-argv"; yt --dry-run --epic DEV-1 >/dev/null
check "youtrack: curl was called, token not in its argv" '[ -s "$STUB_LOG/curl-argv" ] && ! grep -qF "$YT_TOK" "$STUB_LOG/curl-argv" && ! grep -q "Authorization" "$STUB_LOG/curl-argv"'

# Y7. every unreadable answer stops the run (rc 2), never reads as "none" or "ready"
for f in "#Unresolved sort by" "is required for: DEV-5"; do
  YT_FAIL="$f" yt --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
  check "youtrack: failure on '$f' → rc 2" '[ $rc -eq 2 ] && grep -q "task-wave:" "$TMP/err"'
done
YT_FAIL_PAGE2='project: DEV' yt --dry-run --project DEV >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: the list fails on page 2 → rc 2" '[ $rc -eq 2 ]'
YT_HTML=1 yt --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: an HTML page (wrong base URL) → rc 2 naming YOUTRACK_URL" '[ $rc -eq 2 ] && grep -q "YOUTRACK_URL" "$TMP/err"'

# Y8. explicit ids: canonical from the server, deduplicated; unknown → stop; readiness not checked
out="$(yt --dry-run dev-5 DEV-05 DEV-5)"; rc=$?
check "youtrack: 'dev-5 DEV-05 DEV-5' → one plan entry DEV-5" '[ $rc -eq 0 ] && [ "$(ytids "$out")" = "DEV-5 " ]'
out="$(yt --dry-run DEV-3)"
check "youtrack: an explicit id is planned even when blocked" '[ "$(ytids "$out")" = "DEV-3 " ]'
out="$(yt --dry-run DEV-4)"
check "youtrack: explicit DEV-4 without a builder tag → skipped" 'printf "%s" "$out" | grep -q "DEV-4 has no builder"'
yt --dry-run DEV-9999 >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack: an unknown id → rc 2" '[ $rc -eq 2 ] && grep -q "DEV-9999" "$TMP/err"'
yt --dry-run 42 >/dev/null 2>&1; rc=$?
check "youtrack: '42' is not a YouTrack id → rc 2" '[ $rc -eq 2 ]'

# Y9. youtrack needs curl and jq, not gh
mkdir -p "$TMP/nocurl" "$TMP/nogh"
for c in jq dirname basename bash awk sort seq sed tr wc tmux; do ln -sf "$(command -v $c)" "$TMP/nocurl/$c"; done
ln -sf "$TMP/bin/git" "$TMP/nocurl/git"
PATH="$TMP/nocurl" "$TMP/nocurl/bash" "$TW" --tracker youtrack --dry-run --epic DEV-1 >/dev/null 2>"$TMP/err"; rc=$?
check "youtrack without curl → rc 2" '[ $rc -eq 2 ] && grep -q "curl is not on PATH" "$TMP/err"'
for c in jq dirname basename bash awk sort seq sed tr wc tmux cat; do ln -sf "$(command -v $c)" "$TMP/nogh/$c"; done
ln -sf "$TMP/bin/git" "$TMP/nogh/git"; ln -sf "$TMP/bin/curl" "$TMP/nogh/curl"
out="$(PATH="$TMP/nogh" "$TMP/nogh/bash" "$TW" --tracker youtrack --dry-run --epic DEV-1)"; rc=$?
check "youtrack without gh on PATH → works" '[ $rc -eq 0 ] && [ "$(ytids "$out")" = "DEV-2 DEV-5 " ]'

# Y10. the real run: worktrees from origin/HEAD, windows named by id, the prompt byte-exact
rm -f "$STUB_LOG/fetches"
yt --epic DEV-1 > "$TMP/run.out"; rc=$?
check "youtrack run exits 0, one fetch" '[ $rc -eq 0 ] && [ "$(fetches)" = 1 ]'
check "youtrack: worktrees lab-DEV-2 / lab-DEV-5 on task-DEV-2 / task-DEV-5 at origin/main" '[ "$(git -C "$TMP/w/lab-DEV-2" branch --show-current)" = task-DEV-2 ] && [ "$(git -C "$TMP/w/lab-DEV-5" branch --show-current)" = task-DEV-5 ] && [ "$(git -C "$TMP/w/lab-DEV-2" rev-parse HEAD)" = "$MAIN_SHA" ]'
check "youtrack: windows DEV-2 and DEV-5" '[ "$(tmux list-windows -t =wave-lab -F "#{window_name}" | sort | tr "\n" " ")" = "DEV-2 DEV-5 " ]'
for i in $(seq 1 20); do [ -s "$STUB_LOG/claude-lab-DEV-2" ] && [ -s "$STUB_LOG/codex-lab-DEV-5" ] && break; sleep 0.3; done
check "youtrack: claude ran in lab-DEV-2 with /task-flow:task DEV-2" '[ "$(sed -n 1p "$STUB_LOG/claude-lab-DEV-2")" = "$TMP/w/lab-DEV-2" ] && [ "$(sed -n 2p "$STUB_LOG/claude-lab-DEV-2")" = "/task-flow:task DEV-2" ]'
check "youtrack: codex ran in lab-DEV-5 with \$task-flow:task DEV-5" '[ "$(sed -n 2p "$STUB_LOG/codex-lab-DEV-5")" = "\$task-flow:task DEV-5" ]'

# Y11. a live window is matched on its whole name: DEV-2 running does not hide DEV-25,
#      and dev-02 is DEV-2, already running
out="$(yt dev-02)"
check "youtrack: dev-02 is DEV-2, already running → not started again" 'printf "%s" "$out" | grep -q "DEV-2 is already running"'
tmux kill-window -t "=wave-lab:DEV-2"; tmux new-window -t "=wave-lab" -n DEV-25 "sleep 60"
out="$(yt --dry-run DEV-2)"
check "youtrack: a live DEV-25 window does not count as DEV-2" '! printf "%s" "$out" | grep -q "already running" && printf "%s" "$out" | grep -q "exists — resuming"'
tmux kill-server >/dev/null 2>&1 || true

# Y12. --base still wins over origin/HEAD
out="$(yt --dry-run --base develop DEV-7)"
check "youtrack: --base develop → a new worktree from origin/develop" 'printf "%s" "$out" | grep -qF "lab-DEV-7 -b task-DEV-7 origin/develop"'

echo "tests/task-wave: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
