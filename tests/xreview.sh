#!/usr/bin/env bash
# tests/xreview.sh — negative controls for templates/xreview/xreview.sh with
# stub reviewer CLIs: no network, no model. Each case states what the script
# must do with one reviewer answer or one broken input.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
XR="$ROOT/templates/xreview/xreview.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

# --- stub CLIs: record argv, env and the brief; answer from $STUB_ANSWER ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG/argv"; env > "$STUB_LOG/env"; cat > "$STUB_LOG/brief"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
echo "model: stub-codex-1" >&2
[ "${STUB_RC:-0}" = 0 ] || { echo "stub: simulated failure" >&2; exit "$STUB_RC"; }
[ -z "${STUB_ANSWER:-}" ] || cp "$STUB_ANSWER" "$out"
EOF
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG/argv"; env > "$STUB_LOG/env"; cat > "$STUB_LOG/brief"
[ "${STUB_RC:-0}" = 0 ] || { echo "stub: simulated failure" >&2; exit "$STUB_RC"; }
[ -z "${STUB_ANSWER:-}" ] || cat "$STUB_ANSWER"
EOF
chmod +x "$TMP/bin/codex" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/log"
mkdir -p "$STUB_LOG"

# --- a repository with one reviewed change ---
R="$TMP/repo"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf 'one\n' > "$R/app.txt"; git -C "$R" add app.txt; git -C "$R" commit -qm base
git -C "$R" switch -qc feature
printf 'two\n' >> "$R/app.txt"; git -C "$R" commit -qam 'feat: second line'
mkdir -p "$R/docs/specs"
cat > "$R/docs/specs/T-1.spec.md" <<'EOF'
# T-1
## 1. Problem
literal-[HEAD_SHA]-marker and a & b \1 stay text
```
## not a heading inside a fence
```
## 6. DoD → check table
| DoD-1 | app.txt has a second line | diff |
## 7. Premortem edges (filled in by phases 2 and 4)
- EDGE-MARKER-42: empty file
## 8. Failure signal
none
EOF
HEAD_SHA=$(git -C "$R" rev-parse HEAD)

answer() {  # name, body → file
  printf '%s\n' "$2" > "$TMP/$1.md"; printf '%s' "$TMP/$1.md"
}
run() {  # expected-rc, name, [env...] -- xreview args
  local expect="$1" name="$2"; shift 2
  local envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$STUB_LOG"/*
  local rc=0
  OUT=$(cd "$R" && env ${envs[@]+"${envs[@]}"} bash "$XR" "$@" 2> "$TMP/stderr") || rc=$?
  ERR=$(cat "$TMP/stderr")
  if [ "$rc" = "$expect" ]; then ok; else bad "$name: rc=$rc expected=$expect"; printf '%s\n' "$ERR" >&2; fi
}
SHORT=${HEAD_SHA:0:7}

YES=$(answer yes "### Findings
нет
### Assessment
**Reviewed:** $SHORT
**Ready to merge?** Yes
**Reasoning:** ок")
FIXES=$(answer fixes "**Reviewed:** $HEAD_SHA
**Ready to merge?** With fixes")
NO=$(answer no "**Reviewed:** \`$SHORT\`
**Ready to merge?** No")
TRANSLATED=$(answer translated "**Проверено:** $SHORT
**Готово к мержу?** Да")
OTHER_SHA=$(answer othersha "**Reviewed:** 0123456789abcdef
**Ready to merge?** Yes")
NO_SHA=$(answer nosha "**Ready to merge?** Yes")
SEC_CLEAN=$(answer secclean "### Summary
Critical: 0 | High: 0 | Medium: 2 | Low: 1
### Assessment
**Reviewed:** $SHORT")
SEC_HIGH=$(answer sechigh "### Summary
**Critical:** 0 | **High:** 2 | **Medium:** 0 | **Low:** 0
**Reviewed:** $SHORT")
SEC_NOSUM=$(answer secnosum "Всё хорошо.
**Reviewed:** $SHORT")
ECHOED=$(answer echoed "**Reviewed:** $SHORT
**Ready to merge?** [Yes | No | With fixes]")
LONGER_WORD=$(answer longerword "**Reviewed:** $SHORT
**Ready to merge?** Yesterday")
LONGER_SHA=$(answer longersha "**Reviewed:** ${HEAD_SHA}deadbeef
**Ready to merge?** Yes")
TWO_VERDICTS=$(answer twoverdicts "**Reviewed:** $SHORT
**Ready to merge?** Yes
**Ready to merge?** No")
TWO_SHAS=$(answer twoshas "**Reviewed:** $SHORT
Reviewed: 0123456
**Ready to merge?** Yes")
DOTTED=$(answer dotted "**Reviewed:** $SHORT.
**Ready to merge?** With fixes.")
SEC_ECHOED=$(answer secechoed "Critical: N | High: N | Medium: N | Low: N
**Reviewed:** $SHORT")
SHA_LIST=$(answer shalist "Reviewed: $HEAD_SHA, 0123456789abcdef
**Ready to merge?** Yes")
SHA_SUFFIX=$(answer shasuffix "Reviewed: $HEAD_SHA-not-reviewed
**Ready to merge?** Yes")
SEC_TWO=$(answer sectwo "Critical: 0 | High: 0 | Medium: 0 | Low: 0
Critical: 0 | High: 1 | Medium: 0 | Low: 0.
**Reviewed:** $SHORT")
QUOTED=$(answer quoted "Пример неверного ответа:
\`\`\`text
Reviewed: 0123456
Ready to merge? No
\`\`\`
> Reviewed: 0123456
Поле \`Reviewed: 0123456\` в прозе — не вердикт.
**Reviewed:** $SHORT
**Ready to merge?** Yes")

# 1. verdict → exit, both reviewers, report named <TASK>-<sha7>-<by>
run 0 codex-yes "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main
[ -f "$R/docs/reviews/T-1-$SHORT-codex.md" ] && ok || bad "codex report not at docs/reviews/T-1-$SHORT-codex.md"
grep -q 'model: stub-codex-1' "$R/docs/reviews/T-1-$SHORT-codex.md" && ok || bad "report header lacks the model codex reported"
grep -q 'ready to merge → exit 0' "$R/docs/reviews/T-1-$SHORT-codex.md" && ok || bad "report header lacks the verdict"
[ "$OUT" = "docs/reviews/T-1-$SHORT-codex.md" ] && ok || bad "stdout is not the report path: $OUT"
run 0 claude-yes "STUB_ANSWER=$YES" -- --by claude --task T-1 --base main
[ -f "$R/docs/reviews/T-1-$SHORT-claude.md" ] && ok || bad "claude report missing"
run 1 with-fixes "STUB_ANSWER=$FIXES" -- --by codex --task T-1 --base main
run 1 not-ready "STUB_ANSWER=$NO" -- --by claude --task T-1 --base main
# 2. an answer the script cannot read is not clean
run 2 translated-labels "STUB_ANSWER=$TRANSLATED" -- --by codex --task T-1 --base main
grep -q 'unreadable' "$R/docs/reviews/T-1-$SHORT-codex.md" && ok || bad "an unreadable verdict is not recorded as unreadable in the report"
run 2 other-sha "STUB_ANSWER=$OTHER_SHA" -- --by codex --task T-1 --base main
run 2 no-reviewed-line "STUB_ANSWER=$NO_SHA" -- --by claude --task T-1 --base main
# 2b. strict fields: an echoed placeholder, a longer word, a longer sha or two
#     disagreeing lines are unreadable; trailing punctuation is not
run 2 echoed-placeholder "STUB_ANSWER=$ECHOED" -- --by codex --task T-1 --base main
run 2 longer-word "STUB_ANSWER=$LONGER_WORD" -- --by codex --task T-1 --base main
run 2 longer-sha "STUB_ANSWER=$LONGER_SHA" -- --by codex --task T-1 --base main
run 2 two-verdicts "STUB_ANSWER=$TWO_VERDICTS" -- --by codex --task T-1 --base main
run 2 two-shas "STUB_ANSWER=$TWO_SHAS" -- --by codex --task T-1 --base main
run 1 trailing-dots "STUB_ANSWER=$DOTTED" -- --by codex --task T-1 --base main
run 2 security-echoed-summary "STUB_ANSWER=$SEC_ECHOED" -- --by codex --task T-1 --base main --kind security
run 2 sha-then-list "STUB_ANSWER=$SHA_LIST" -- --by codex --task T-1 --base main
run 2 sha-then-suffix "STUB_ANSWER=$SHA_SUFFIX" -- --by codex --task T-1 --base main
run 2 security-two-summaries "STUB_ANSWER=$SEC_TWO" -- --by codex --task T-1 --base main --kind security
run 0 quoted-fields-ignored "STUB_ANSWER=$QUOTED" -- --by codex --task T-1 --base main
# 3. security brief: counts decide, bold or not
run 0 security-clean "STUB_ANSWER=$SEC_CLEAN" -- --by codex --task T-1 --base main --kind security
[ -f "$R/docs/reviews/T-1-$SHORT-codex-security.md" ] && ok || bad "security report not suffixed -security"
run 1 security-high "STUB_ANSWER=$SEC_HIGH" -- --by claude --task T-1 --base main --kind security
run 2 security-no-summary "STUB_ANSWER=$SEC_NOSUM" -- --by codex --task T-1 --base main --kind security
# 4. no review happened → 2, and the reviewer is never called on a bad range
run 2 empty-range "STUB_ANSWER=$YES" -- --by codex --task T-1 --base feature
[ ! -e "$STUB_LOG/argv" ] && ok || bad "the reviewer was dispatched on an empty range"
run 2 no-spec "STUB_ANSWER=$YES" -- --by codex --task T-2 --base main
printf '# T-3\n## 1. Problem\nx\n' > "$R/docs/specs/T-3.spec.md"
run 2 spec-without-dod "STUB_ANSWER=$YES" -- --by codex --task T-3 --base main
run 2 cli-missing "STUB_ANSWER=$YES" "XREVIEW_CODEX_BIN=$TMP/nope" -- --by codex --task T-1 --base main
run 2 cli-fails "STUB_ANSWER=$YES" STUB_RC=1 -- --by claude --task T-1 --base main
printf '%s' "$ERR" | grep -q 'simulated failure' && ok || bad "a failed reviewer's stderr is not shown"
run 2 cli-silent "STUB_ANSWER=" -- --by codex --task T-1 --base main
run 2 bad-base "STUB_ANSWER=$YES" -- --by codex --task T-1 --base origin/nope
# 5. the brief: slots from the spec, literal, the right sections per kind
run 0 brief-code "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main
B="$STUB_LOG/brief"
grep -q 'DoD-1 | app.txt has a second line' "$B" && ok || bad "code brief lacks the DoD section"
grep -q 'EDGE-MARKER-42' "$B" && ok || bad "code brief lacks the premortem edges"
grep -qF 'literal-[HEAD_SHA]-marker and a & b \1 stay text' "$B" && ok || bad "spec text was not inserted literally"
grep -q "$HEAD_SHA" "$B" && ok || bad "code brief lacks the head sha"
grep -q 'feat: second line' "$B" && ok || bad "default WHAT_CHANGED is not the commit subjects"
grep -v 'literal-' "$B" | grep -qE '\[(DOD|DESIGN_SPEC|PREMORTEM_EDGES|WHAT_CHANGED|BASE_SHA|HEAD_SHA)\]' && bad "an unfilled slot reached the reviewer" || ok
run 0 brief-security "STUB_ANSWER=$SEC_CLEAN" -- --by claude --task T-1 --base main --kind security
grep -q 'EDGE-MARKER-42' "$STUB_LOG/brief" && bad "the security brief received the premortem edges" || ok
grep -q 'DoD-1' "$STUB_LOG/brief" && ok || bad "security brief lacks the design spec"
grep -q '\[DATA_AND_GRANTS\]' "$STUB_LOG/brief" && bad "DATA_AND_GRANTS left unfilled" || ok
run 0 brief-only -- --by codex --task T-1 --base main --brief-only
[ ! -e "$STUB_LOG/argv" ] && ok || bad "--brief-only dispatched the reviewer"
printf '%s' "$OUT" | grep -q 'DoD-1' && ok || bad "--brief-only did not print the brief"
# 6. read-only and isolated by default; no session identity crosses over
run 0 codex-flags "STUB_ANSWER=$YES" CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=author CLAUDE_CODE_MESSAGING_TOKEN=tok PP_SESSION=pp CODEX_SESSION_ID=cx PREDICT=/x -- --by codex --task T-1 --base main
A="$STUB_LOG/argv"
for f in exec -s read-only --ignore-user-config --ephemeral; do grep -qxF -- "$f" "$A" && ok || bad "codex argv lacks $f"; done
for v in CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_TOKEN PP_SESSION CODEX_SESSION_ID PREDICT; do
  grep -q "^$v=" "$STUB_LOG/env" && bad "the reviewer inherited $v" || ok
done
grep -q '^HOME=' "$STUB_LOG/env" && ok || bad "scrub removed HOME (auth lives there)"
run 0 scrub-families "STUB_ANSWER=$YES" CLAUDE_CODE_REVIEW_SENTINEL=a CLAUDE_PLUGIN_REVIEW_SENTINEL=a PP_ANY=a CODEX_THREAD_ID=a CODEX_SANDBOX_NETWORK_DISABLED=1 CLAUDE_CODE_OAUTH_TOKEN=keep CLAUDE_CODE_USE_BEDROCK=1 CODEX_HOME=/keep -- --by claude --task T-1 --base main
for v in CLAUDE_CODE_REVIEW_SENTINEL CLAUDE_PLUGIN_REVIEW_SENTINEL PP_ANY CODEX_THREAD_ID CODEX_SANDBOX_NETWORK_DISABLED; do
  grep -q "^$v=" "$STUB_LOG/env" && bad "the reviewer inherited $v (a family member, not a listed name)" || ok
done
for v in CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CODEX_HOME; do
  grep -q "^$v=" "$STUB_LOG/env" && ok || bad "scrub removed $v (the reviewer's own auth / provider selection)"
done
run 0 keep-env "STUB_ANSWER=$YES" CLAUDE_CODE_REVIEW_SENTINEL=a "XREVIEW_KEEP_ENV=CLAUDE_CODE_REVIEW_SENTINEL" -- --by codex --task T-1 --base main
grep -q '^CLAUDE_CODE_REVIEW_SENTINEL=' "$STUB_LOG/env" && ok || bad "XREVIEW_KEEP_ENV did not keep the named variable"
run 2 bad-effort "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main --effort 'high" sandbox_mode="danger-full-access'
[ ! -e "$STUB_LOG/argv" ] && ok || bad "an unvalidated --effort reached the reviewer CLI"
run 0 claude-flags "STUB_ANSWER=$YES" -- --by claude --task T-1 --base main --model opus
A="$STUB_LOG/argv"
for f in -p --setting-sources local --permission-mode dontAsk --tools Read,Grep,Glob --no-session-persistence --model opus \
         --strict-mcp-config '{"mcpServers":{}}' --disable-slash-commands; do
  grep -qxF -- "$f" "$A" && ok || bad "claude argv lacks $f"
done
grep -q '^Bash' "$A" && bad "the claude reviewer has a shell by default (git diff --output writes)" || ok
grep -q '^## Range material' "$STUB_LOG/brief" && ok || bad "the claude brief lacks the attached range material"
grep -q '^+two$' "$STUB_LOG/brief" && ok || bad "the attached range material lacks the diff"
grep -q 'feat: second line' "$STUB_LOG/brief" && ok || bad "the attached range material lacks the log"
run 0 claude-allow "STUB_ANSWER=$YES" "XREVIEW_ALLOW=Bash(make test)" -- --by claude --task T-1 --base main
grep -A1 -xF -- --tools "$STUB_LOG/argv" | tail -n 1 | grep -qx 'Read,Grep,Glob,Bash' && ok || bad "XREVIEW_ALLOW did not grant the shell"
grep -qxF 'Bash(make test)' "$STUB_LOG/argv" && ok || bad "XREVIEW_ALLOW rule missing from --allowedTools"
grep -q '^Bash(git' "$STUB_LOG/argv" && bad "XREVIEW_ALLOW brought back the git allowlist" || ok
run 2 claude-diff-cap "STUB_ANSWER=$YES" XREVIEW_MAX_DIFF_BYTES=10 -- --by claude --task T-1 --base main
[ ! -e "$STUB_LOG/argv" ] && ok || bad "an over-cap diff was dispatched (truncated review)"
run 0 codex-no-material "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main
grep -q '^## Range material' "$STUB_LOG/brief" && bad "the codex brief got range material (it has its own read-only shell)" || ok
# the claude reviewer reads the checkout: another head is refused; codex runs git itself
git -C "$R" switch -qc two; printf 'three\n' >> "$R/app.txt"; git -C "$R" commit -qam 'feat: third line'
run 2 claude-other-head "STUB_ANSWER=$YES" -- --by claude --task T-1 --base main --head feature
run 0 codex-other-head "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main --head feature
# a fence in the material is longer than any backtick run inside it
printf '%s\n' '```````' > "$R/fence.md"; git -C "$R" add fence.md; git -C "$R" commit -qm 'docs: backticks'
TWO_SHA=$(git -C "$R" rev-parse HEAD)
answer two "**Reviewed:** $TWO_SHA
**Ready to merge?** Yes" > /dev/null
run 0 claude-fence "STUB_ANSWER=$TMP/two.md" -- --by claude --task T-1 --base main
grep -qE '^`{8,}text$' "$STUB_LOG/brief" && ok || bad "the material fence is not longer than the 7-backtick run inside it"
# 6b material leaves out the spec's own diff when the spec is in the range
git -C "$R" add docs/specs/T-1.spec.md; git -C "$R" commit -qm 'docs: spec'
SPEC_SHA=$(git -C "$R" rev-parse HEAD)
answer spec "Critical: 0 | High: 0 | Medium: 0 | Low: 0
**Reviewed:** $SPEC_SHA" > /dev/null
run 0 claude-security-spec "STUB_ANSWER=$TMP/spec.md" -- --by claude --task T-1 --base main --kind security
grep -q 'EDGE-MARKER-42' "$STUB_LOG/brief" && bad "the 6b material carries the spec's premortem edges through its diff" || ok
grep -q 'fence.md' "$STUB_LOG/brief" && ok || bad "the 6b material lost the rest of the diff"
git -C "$R" switch -q feature
git -C "$R" show two:docs/specs/T-1.spec.md > "$R/docs/specs/T-1.spec.md"   # committed on the side branch; untracked again here
grep -qxE '(Edit|Write|MultiEdit|NotebookEdit|Agent)' "$A" && bad "claude reviewer gets a write or dispatch tool" || ok
grep -A1 -xF -- --tools "$A" | tail -n 1 | grep -qE 'Edit|Write|Agent' && bad "--tools offers a write or dispatch tool" || ok
run 0 not-isolated "STUB_ANSWER=$YES" XREVIEW_ISOLATE=0 -- --by codex --task T-1 --base main
grep -qxF -- --ignore-user-config "$STUB_LOG/argv" && bad "XREVIEW_ISOLATE=0 still isolates" || ok
run 0 claude-not-isolated "STUB_ANSWER=$YES" XREVIEW_ISOLATE=0 -- --by claude --task T-1 --base main
A="$STUB_LOG/argv"
grep -qxF 'user,local' "$A" && ok || bad "XREVIEW_ISOLATE=0 does not bring the user's plugins back"
grep -qxF 'project' "$A" || grep -qE '^(project|.*,project)(,|$)' "$A" && bad "the project's settings (hooks from the diff) reach the claude reviewer" || ok
grep -qxF -- --strict-mcp-config "$A" && ok || bad "XREVIEW_ISOLATE=0 lets MCP servers (write tools) back in"
git -C "$R" diff --quiet && ok || bad "the review modified a tracked file"

echo "tests/xreview: $pass passed, $fail failed"
[ "$fail" = 0 ]
