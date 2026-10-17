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
for a in claude codex; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" "$@" > "$STUB_LOG/%s-$(basename "$PWD")"; echo x >> "$STUB_LOG/launches-%s-$(basename "$PWD")"; sleep 60\n' "$a" "$a" > "$TMP/bin/$a"
done
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" FX="$F" STUB_LOG="$TMP/log"
fetches() { if [ -f "$STUB_LOG/fetches" ]; then wc -l < "$STUB_LOG/fetches" | tr -d ' '; else echo 0; fi; }

# --- a repository with an origin: main, and develop one commit ahead
git init -q --bare "$TMP/origin.git"
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
ln -sf "$TMP/bin/git" "$TMP/nocodex/git"; ln -sf "$TMP/bin/claude" "$TMP/nocodex/claude"
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

# 5c. a number named twice → one plan entry, one window, one launch (new worktree, then resumed)
bash "$TW" 2 2 >/dev/null 2>&1; rc=$?
check "'2 2' on a new worktree → one window, one claude launch" '[ $rc -eq 0 ] && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 1 ] && [ "$(wc -l < "$STUB_LOG/launches-claude-lab-2")" -eq 1 ]'
tmux kill-server >/dev/null 2>&1 || true
bash "$TW" 2 '#2' >/dev/null 2>&1; rc=$?
check "'2 #2' on the existing worktree → one window, one more launch" '[ $rc -eq 0 ] && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 1 ] && [ "$(wc -l < "$STUB_LOG/launches-claude-lab-2")" -eq 2 ]'
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
check "still two windows and one claude launch in lab-2" '[ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 2 ] && [ "$(wc -l < "$STUB_LOG/launches-claude-lab-2")" -eq 1 ]'
# … and once that window is gone (the agent exited), the same worktree is resumed in a new one
tmux kill-window -t "=wave-lab:#2"
out="$(bash "$TW" 2)"
check "window gone → existing worktree resumed in a new window" 'printf "%s" "$out" | grep -q "exists — resuming" && [ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 2 ]'

# 7b. two launchers at once on a resumable task: one starts it, the other is refused — never two agents
tmux kill-window -t "=wave-lab:#2"; rm -f "$STUB_LOG/launches-claude-lab-2"
GH_SLOW=1 bash "$TW" 2 >"$TMP/a.out" 2>"$TMP/a.err" & pa=$!
sleep 0.3
GH_SLOW=1 bash "$TW" 2 >"$TMP/b.out" 2>"$TMP/b.err"; rb=$?
wait $pa; ra=$?
for i in $(seq 1 20); do [ -s "$STUB_LOG/launches-claude-lab-2" ] && break; sleep 0.2; done; sleep 0.5
check "concurrent run: first starts #2, second refused by the lock" '[ $ra -eq 0 ] && [ $rb -eq 2 ] && grep -q "another task-wave holds" "$TMP/b.err"'
check "concurrent run: one window #2, one launch" '[ "$(tmux list-windows -t =wave-lab -F "#{window_name}" | grep -cx "#2")" -eq 1 ] && [ "$(wc -l < "$STUB_LOG/launches-claude-lab-2")" -eq 1 ]'
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

echo "tests/task-wave: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
