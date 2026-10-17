#!/usr/bin/env bash
# tests/task-wave.sh — negative controls for templates/wave/task-wave.sh with a
# stub `gh` (fixture JSON through the script's own jq filters), stub `claude` /
# `codex` that record their argv and cwd, and a private tmux server. No network,
# no model.
set -uo pipefail   # no -e: cases assert non-zero exits themselves
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TW="$ROOT/templates/wave/task-wave.sh"
TMP=$(mktemp -d)
export TMUX_TMPDIR="$TMP/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
trap 'tmux kill-server >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }
check() { if eval "$2"; then ok; else bad "$1"; fi; }
command -v jq >/dev/null || { echo "tests/task-wave.sh: jq is required (the gh stub runs the script's -q filters through it)" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tests/task-wave.sh: tmux is required" >&2; exit 1; }

# --- fixtures: #2 claude, blocker closed · #3 codex, blocker open · #4 no label · #5 codex, no blockers
F="$TMP/fx"; mkdir -p "$F"
cat > "$F/list.json" <<'EOF'
[{"number":2,"labels":[{"name":"builder:claude"}]},
 {"number":3,"labels":[{"name":"builder:codex"}]},
 {"number":4,"labels":[{"name":"epic"}]},
 {"number":5,"labels":[{"name":"bug"},{"name":"builder:codex"}]}]
EOF
echo '[{"number":1,"state":"closed"}]' > "$F/blocked-2.json"
echo '[{"number":2,"state":"open"}]'   > "$F/blocked-3.json"
echo '[]'                             > "$F/blocked-5.json"
for n in 2 3 4 5; do jq "{labels: (.[] | select(.number == $n) | .labels)}" "$F/list.json" > "$F/issue-$n.json"; done
echo '{"nameWithOwner":"o/lab","defaultBranchRef":{"name":"main"}}' > "$F/repo.json"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
# answer from fixtures; run the caller's -q filter with jq, as gh does
q=""; prev=""; for a in "$@"; do [ "$prev" = "-q" ] && q="$a"; prev="$a"; done
[ "${GH_FAIL:-}" = "$1 $2" ] && { echo "gh: simulated failure" >&2; exit 1; }
case "$1 $2" in
  "repo view")  f="$FX/repo.json" ;;
  "issue list") f="$FX/list.json" ;;
  "issue view") f="$FX/issue-$3.json" ;;
  api\ *)       n="${2#repos/o/lab/issues/}"; n="${n%%/*}"; f="$FX/blocked-$n.json" ;;
  *) echo "gh stub: unexpected: $*" >&2; exit 3 ;;
esac
[ -f "$f" ] || { echo "gh stub: no fixture $f" >&2; exit 4; }
jq -r "$q" "$f"
EOF
for a in claude codex; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" "$@" > "$STUB_LOG/%s-$(basename "$PWD")"; sleep 60\n' "$a" > "$TMP/bin/$a"
done
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" FX="$F" STUB_LOG="$TMP/log"; mkdir -p "$STUB_LOG"

# --- a repository with an origin, so worktrees start from origin/main
git init -q --bare "$TMP/origin.git"
git init -q -b main "$TMP/w/lab"; cd "$TMP/w/lab"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git remote add origin "$TMP/origin.git"; git push -q origin main

# 1. dry run on the ready set: #2 and #5 only, nothing created
out="$(bash "$TW" --dry-run)"; rc=$?
check "dry run exits 0" '[ $rc -eq 0 ]'
check "dry run: ready set is #2 and #5" 'printf "%s" "$out" | grep -q "^#2 builder:claude" && printf "%s" "$out" | grep -q "^#5 builder:codex" && ! printf "%s" "$out" | grep -qE "^#(3|4) "'
check "dry run: claude gets /task-flow:task #2" 'printf "%s" "$out" | grep -qF "claude /task-flow:task\\ #2"'
check "dry run: codex gets \$task-flow:task #5, the \$ escaped for the shell" 'printf "%s" "$out" | grep -qF "codex \\\$task-flow:task\\ #5"'
check "dry run creates no worktree and no tmux session" '[ "$(git worktree list | wc -l)" -eq 1 ] && ! tmux has-session -t =wave-lab 2>/dev/null'

# 2. an explicit issue without a builder label is skipped, not guessed
out="$(bash "$TW" --dry-run 4)"
check "explicit #4 without builder label → skipped" 'printf "%s" "$out" | grep -q "#4 has no builder"'
bash "$TW" --dry-run abc >/dev/null 2>&1 && bad "a non-number argument must be refused" || ok

# 3. a broken tracker read stops the run instead of reporting "no ready task"
GH_FAIL="issue list" bash "$TW" --dry-run >/dev/null 2>"$TMP/err"; rc=$?
check "gh issue list failure → rc 2" '[ $rc -eq 2 ] && grep -q "cannot list" "$TMP/err"'
GH_FAIL="api repos/o/lab/issues/2/dependencies/blocked_by" bash "$TW" --dry-run >/dev/null 2>"$TMP/err"; rc=$?
check "blocked-by read failure → rc 2, not 'ready'" '[ $rc -eq 2 ] && grep -q "refusing to guess" "$TMP/err"'

# 4. no tmux (not a dry run) → refused before anything is created
mkdir -p "$TMP/notmux"; for c in git gh jq dirname basename bash; do ln -sf "$(command -v $c)" "$TMP/notmux/$c"; done
PATH="$TMP/notmux" "$TMP/notmux/bash" "$TW" 2 >/dev/null 2>"$TMP/err"; rc=$?
check "no tmux → rc 2, no worktree" '[ $rc -eq 2 ] && grep -q "tmux is not on PATH" "$TMP/err" && [ "$(git worktree list | wc -l)" -eq 1 ]'

# 5. the real run: one worktree per task from origin/main, one tmux window each, the right CLI and prompt
bash "$TW" > "$TMP/run.out"; rc=$?
check "run exits 0 and names the session" '[ $rc -eq 0 ] && grep -q "tmux attach -t wave-lab" "$TMP/run.out"'
check "worktrees lab-2 and lab-5 on task-2 / task-5" '[ "$(git -C "$TMP/w/lab-2" branch --show-current)" = task-2 ] && [ "$(git -C "$TMP/w/lab-5" branch --show-current)" = task-5 ] && [ ! -e "$TMP/w/lab-3" ]'
check "windows #2 and #5 in session wave-lab" '[ "$(tmux list-windows -t =wave-lab -F "#{window_name}" | sort | tr "\n" " ")" = "#2 #5 " ]'
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$STUB_LOG/claude-lab-2" ] && [ -s "$STUB_LOG/codex-lab-5" ] && break; sleep 0.3; done
check "claude ran in lab-2 with /task-flow:task #2" '[ "$(sed -n 1p "$STUB_LOG/claude-lab-2")" = "$TMP/w/lab-2" ] && [ "$(sed -n 2p "$STUB_LOG/claude-lab-2")" = "/task-flow:task #2" ]'
check "codex ran in lab-5 with \$task-flow:task #5" '[ "$(sed -n 1p "$STUB_LOG/codex-lab-5")" = "$TMP/w/lab-5" ] && [ "$(sed -n 2p "$STUB_LOG/codex-lab-5")" = "\$task-flow:task #5" ]'

# 6. a second run resumes in the existing worktree and adds a window to the same session
out="$(bash "$TW" 2)"
check "existing worktree → resumed, not recreated" 'printf "%s" "$out" | grep -q "worktree exists — resuming"'
check "second window for #2 joins wave-lab" '[ "$(tmux list-windows -t =wave-lab | wc -l)" -eq 3 ]'

# 7. a branch left behind by a removed worktree is reused, not re-created from base
tmux kill-server >/dev/null 2>&1 || true
git worktree remove --force "$TMP/w/lab-5"
out="$(bash "$TW" 5)"
check "branch task-5 without worktree → reused" 'printf "%s" "$out" | grep -q "(branch exists)" && [ "$(git -C "$TMP/w/lab-5" branch --show-current)" = task-5 ]'

# 8. --base takes another integration branch
git push -q origin main:develop
out="$(bash "$TW" --dry-run --base develop 2)"
git worktree remove --force "$TMP/w/lab-2"; git branch -q -D task-2
out="$(bash "$TW" --dry-run --base develop 2)"
check "--base develop names origin/develop" 'printf "%s" "$out" | grep -qF -- "-b task-2 origin/develop"'

echo "tests/task-wave: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
