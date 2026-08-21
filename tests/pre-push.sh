#!/usr/bin/env bash
# tests/pre-push.sh — negative controls for templates/ci-gate/ci/pre-push.sh.
# Needs network once (pinned gitleaks); set GITLEAKS_CACHE_DIR to reuse a cache.
#
# A bare remote + a clone. Each control feeds the hook what git would (native
# stdin lines) or what pre-commit would (PRE_COMMIT_* env) and checks the exit:
# 0 nothing secret leaves · 1 a secret is in the commits being pushed ·
# 2 the hook could not tell what is being pushed (must block).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/templates/ci-gate/ci/pre-push.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GITLEAKS_CACHE_DIR="${GITLEAKS_CACHE_DIR:-$TMP/cache}" GITLEAKS_RUN_DIR="$TMP/run" GATE_PINNED_ONLY=1
pass=0; fail=0
Z=0000000000000000000000000000000000000000
# Credential-shaped, assembled at run time: a literal key in a tracked file
# would be flagged by this repository's own secret-scan (and by every consumer's).
SECRET="aws_key = \"AKIA$(printf 'Q4U7W2R5T3Y6P2M4')\""
G() { git -c user.name=t -c user.email=t@t "$@"; }
sha() { git rev-parse "$1"; }

git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/work" 2>/dev/null
cd "$TMP/work"; git checkout -q -b main
mkdir ci; cp "$ROOT"/templates/ci-gate/ci/*.sh ci/; cp "$ROOT/templates/ci-gate/.gitleaks.toml" .
printf 'hello\n' > README.md; G add -A; G commit -qm init; git push -q -u origin main 2>/dev/null

check() {  # name expected stdin-lines [env assignments...]
  local name="$1" expect="$2" lines="$3"; shift 3; local rc out
  out=$(printf '%s\n' "$lines" | env "$@" bash "$HOOK" origin 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$out" >&2; fi
  LAST_OUT="$out"
}

# a) pushed state, nothing new: clean
check up-to-date 0 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
# b) a new commit on main with a secret (remote sha is an ancestor → remote..local)
printf '%s\n' "$SECRET" > cfg.py; G add -A; G commit -qm "add cfg"
check secret-in-new-commit 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
printf '%s\n' "$LAST_OUT" | grep -q "push blocked" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL message: $LAST_OUT" >&2; }
# c) the bypass names THIS push (sha + reason) and leaves a record
check bypass-with-sha-and-reason 0 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)" GATE_PREPUSH_SKIP="$(git rev-parse --short=12 HEAD): hotfix, T-42"
grep -q 'refs=\[main\] sha=.* reason=hotfix, T-42' .git/gate-bypass.log && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL bypass log: $(cat .git/gate-bypass.log 2>&1)" >&2; }
# a value left in a shell profile does not bypass the next push: wrong sha → scan anyway
check bypass-stale-sha 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)" GATE_PREPUSH_SKIP="deadbeef1234: leftover in .zshrc"
printf '%s\n' "$LAST_OUT" | grep -q 'does not name this push' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL stale-sha message: $LAST_OUT" >&2; }
check bypass-reason-only 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)" GATE_PREPUSH_SKIP="hotfix, T-42"
check bypass-sha-without-reason 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)" GATE_PREPUSH_SKIP="$(git rev-parse --short=12 HEAD)"
check bypass-empty-reason 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)" GATE_PREPUSH_SKIP=
[ "$(wc -l < .git/gate-bypass.log)" = 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL a rejected bypass was logged: $(cat .git/gate-bypass.log)" >&2; }
git reset -q --hard origin/main
# d) amend after push: remote sha is no longer an ancestor, the amended commit must still be scanned
printf 'v2\n' >> README.md; G add -A; G commit -qm "v2"; git push -q origin main 2>/dev/null
printf '%s\n' "$SECRET" > cfg.py; G add -A; G commit -q --amend --no-edit
check amend-after-push 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
git reset -q --hard origin/main
# e) secret already ON the remote, new commit clean: incremental — only the new commit is scanned
printf '%s\n' "$SECRET" > old.py; G add -A; G commit -qm "legacy"; git push -q origin main 2>/dev/null
printf 'clean\n' > new.py; G add -A; G commit -qm "new"
check incremental-ignores-pushed-history 0 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
git reset -q --hard origin/main
git rm -q old.py; G commit -qm "remove legacy"; git push -q origin main 2>/dev/null
# f) new branch (remote sha zero): merge-base with the default branch → only the branch's commits
git checkout -q -b feat; printf 'feat\n' > f.txt; G add -A; G commit -qm feat
check new-branch-clean 0 "refs/heads/feat $(sha HEAD) refs/heads/feat $Z"
printf '%s\n' "$SECRET" > f2.txt; G add -A; G commit -qm "oops"
check new-branch-secret 1 "refs/heads/feat $(sha HEAD) refs/heads/feat $Z"
# g) remote sha not known locally (history made on another machine): same fallback, same verdict
check unknown-remote-sha 1 "refs/heads/feat $(sha HEAD) refs/heads/feat deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
# h) several refs in one push: one dirty ref blocks
check multi-ref-one-dirty 1 "refs/heads/main $(sha main) refs/heads/main $(sha origin/main)
refs/heads/feat $(sha HEAD) refs/heads/feat $Z"
# i) deleting a remote ref pushes nothing
check delete-ref 0 "(delete) $Z refs/heads/feat $(sha HEAD)"
printf '%s\n' "$LAST_OUT" | grep -q 'nothing to scan' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL delete should not scan: $LAST_OUT" >&2; }
# j) empty stdin (git pushes nothing): exit 0, no scan
check empty-stdin 0 ""
# k) pre-commit mode: env instead of stdin
check precommit-env-secret 1 "" PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF="$(sha origin/main)" PRE_COMMIT_TO_REF="$(sha HEAD)" PRE_COMMIT_LOCAL_BRANCH=refs/heads/feat
check precommit-env-clean 0 "" PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF="$(sha HEAD~1)" PRE_COMMIT_TO_REF="$(sha HEAD~1)"
# pre-commit "all files" (nothing of the ref on the remote): FROM/TO absent → whole history of HEAD, which holds the secret
check precommit-env-all-files 1 "" PRE_COMMIT_REMOTE_NAME=origin
# l) orphan history with no merge-base: whole history scanned
git checkout -q --orphan solo; git rm -rqf . >/dev/null; git checkout main -- ci .gitleaks.toml; printf '%s\n' "$SECRET" > s.txt; G add -A; G commit -qm solo
check orphan-no-merge-base 1 "refs/heads/solo $(sha HEAD) refs/heads/solo $Z"
# an orphan WITHOUT ci/ in its tree: the native hook cannot find the fetch script → block with a message, not rc 127
git rm -rqf ci .gitleaks.toml >/dev/null; G commit -qm "no ci"
check orphan-without-ci-blocks 2 "refs/heads/solo $(sha HEAD) refs/heads/solo $Z"
printf '%s\n' "$LAST_OUT" | grep -q 'not in the checked-out tree' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL message: $LAST_OUT" >&2; }
git checkout -q -f main; git branch -q -D solo feat
# l2) a secret sitting unpushed on ANOTHER local branch also leaves with this push
git checkout -q main; printf '%s\n' "$SECRET" > stash.py; G add -A; G commit -qm "unpushed on main"
git checkout -q -b sidebranch; printf 'ok\n' > side.txt; G add -A; G commit -qm side
check unpushed-on-other-branch 1 "refs/heads/sidebranch $(sha HEAD) refs/heads/sidebranch $Z"
git checkout -q main; git reset -q --hard origin/main; git branch -q -D sidebranch
# l3) a secret introduced only in a merge commit (evil merge) is still found
git checkout -q -b em; printf 'a\n' > a.txt; G add -A; G commit -qm a; git checkout -q main
git merge -q --no-ff --no-commit em >/dev/null 2>&1 || true
printf '%s\n' "$SECRET" > evil.py; G add -A; G commit -qm "merge em"
check evil-merge 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
git reset -q --hard origin/main; git branch -q -D em
# l4) a `-diff` attribute must not hide a file from the scan
printf '*.py -diff\n' > .gitattributes; printf '%s\n' "$SECRET" > hidden.py; G add -A; G commit -qm "attr"
check gitattributes-minus-diff 1 "refs/heads/main $(sha HEAD) refs/heads/main $(sha origin/main)"
git reset -q --hard origin/main
# m) git breaks while computing the range: block
mkdir -p "$TMP/badgit"; printf '#!/bin/sh\ncase "$1" in -C) echo "git: simulated failure" >&2; exit 128;; esac\nexec /usr/bin/git "$@"\n' > "$TMP/badgit/git"; chmod +x "$TMP/badgit/git"
git checkout -q -b feat2; printf 'x\n' > x.txt; G add -A; G commit -qm x
check broken-git-blocks 2 "refs/heads/feat2 $(sha HEAD) refs/heads/feat2 $Z" PATH="$TMP/badgit:$PATH"
# m2) an unresolvable range blocks instead of being scanned as "0 commits, clean"
check unresolvable-range-blocks 2 "refs/heads/feat2 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef refs/heads/feat2 $Z"
printf '%s\n' "$LAST_OUT" | grep -q 'git cannot run' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL unresolvable-range message: $LAST_OUT" >&2; }
# m3) a git too old for --diff-merges (< 2.31) must block, not scan nothing:
#     inside gitleaks that option error reads as "0 commits scanned, no leaks".
mkdir -p "$TMP/oldgit"; printf '#!/bin/sh\nfor a in "$@"; do case "$a" in --diff-merges*) echo "error: unknown option \\`diff-merges=first-parent'"'"'" >&2; exit 129;; esac; done\nexec /usr/bin/git "$@"\n' > "$TMP/oldgit/git"; chmod +x "$TMP/oldgit/git"
check old-git-without-diff-merges 2 "refs/heads/feat2 $(sha HEAD) refs/heads/feat2 $Z" PATH="$TMP/oldgit:$PATH"
printf '%s\n' "$LAST_OUT" | grep -q 'older than 2.31' && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL old-git message: $LAST_OUT" >&2; }

# n) the scanner itself fails: block, never pass
mkdir -p "$TMP/badgl"; printf '#!/bin/sh\necho "gitleaks: simulated failure" >&2\nexit 3\n' > "$TMP/badgl/gitleaks"; chmod +x "$TMP/badgl/gitleaks"
check broken-scanner-blocks 2 "refs/heads/feat2 $(sha HEAD) refs/heads/feat2 $Z" PATH="$TMP/badgl:$PATH" GATE_PINNED_ONLY=0
git checkout -q main; git branch -q -D feat2
# n2) a GITLEAKS_RUN_DIR the caller provided is the caller's to delete
mkdir -p "$TMP/precious"; printf 'keep me\n' > "$TMP/precious/user-file.txt"
check inherited-run-dir-kept 0 "refs/heads/main $(sha main) refs/heads/main $(sha origin/main)" GITLEAKS_RUN_DIR="$TMP/precious"
[ -f "$TMP/precious/user-file.txt" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL pre-push deleted a run dir it did not create" >&2; }

# o) installed as the native hook (cwd may be anywhere inside the repo, $0 under .git/hooks)
cp "$HOOK" .git/hooks/pre-push; chmod +x .git/hooks/pre-push
git checkout -q -b feat3; printf '%s\n' "$SECRET" > y.txt; G add -A; G commit -qm y
out=$(git push -q origin feat3 2>&1) && rc=0 || rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'push blocked' && ! git -C "$TMP/remote.git" rev-parse --verify --quiet refs/heads/feat3 >/dev/null \
  && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL native hook via git push: rc=%s\n%s\n' "$rc" "$out" >&2; }
out=$(git push -q --no-verify origin feat3 2>&1) && rc=0 || rc=$?   # the documented hole: --no-verify skips the hook
[ "$rc" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL --no-verify should bypass (documented): %s\n' "$out" >&2; }

echo "tests/pre-push: $pass passed, $fail failed"
[ "$fail" = 0 ]
