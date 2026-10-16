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

# A reviewer answer: free prose, then the two plain machine lines.
code() { answer "$1" "### Findings
нет
### Assessment
**Reasoning:** ок
$2"; }
YES=$(code yes "REVIEWED $SHORT
VERDICT yes")
FIXES=$(code fixes "REVIEWED $HEAD_SHA
VERDICT with-fixes")
NO=$(code no "REVIEWED $SHORT
VERDICT no")
SEC_CLEAN=$(answer secclean "### Summary
Critical: 0 | High: 0 | Medium: 2 | Low: 1
### Assessment
REVIEWED $SHORT
SUMMARY critical=0 high=0 medium=2 low=1")
SEC_HIGH=$(answer sechigh "REVIEWED $SHORT
SUMMARY critical=0 high=2 medium=0 low=0")
SEC_LEADING_ZERO=$(answer secoctal "REVIEWED $SHORT
SUMMARY critical=08 high=09 medium=0 low=0")
CRLF=$(answer crlf "$(printf 'REVIEWED %s\r\nVERDICT no\r' "$SHORT")")
# Anything but the exact two last lines is unreadable (2), never clean.
TRANSLATED=$(code translated "ПРОВЕРЕНО $SHORT
ВЕРДИКТ да")
OTHER_SHA=$(code othersha "REVIEWED 0123456789abcdef
VERDICT yes")
NO_SHA=$(code nosha "VERDICT yes")
ECHOED=$(code echoed "REVIEWED $SHORT
VERDICT yes | no | with-fixes")
LONGER_WORD=$(code longerword "REVIEWED $SHORT
VERDICT yesterday")
LONGER_SHA=$(code longersha "REVIEWED ${HEAD_SHA}deadbeef
VERDICT yes")
SHA_LIST=$(code shalist "REVIEWED $HEAD_SHA, 0123456789abcdef
VERDICT yes")
SHA_SUFFIX=$(code shasuffix "REVIEWED $HEAD_SHA-not-reviewed
VERDICT yes")
AFTER=$(code after "REVIEWED $SHORT
VERDICT yes
Спасибо за внимание.")
REVERSED=$(code reversed "VERDICT yes
REVIEWED $SHORT")
DOTTED=$(code dotted "REVIEWED $SHORT
VERDICT yes.")
BOLD=$(code bold "**REVIEWED** $SHORT
**VERDICT** yes")
LEGACY=$(code legacy "**Reviewed:** $SHORT
**Ready to merge?** Yes")
INDENTED=$(code indented "    REVIEWED $SHORT
    VERDICT yes")
FENCED=$(code fenced "\`\`\`
REVIEWED $SHORT
VERDICT yes
\`\`\`")
COMMENTED=$(code commented "<!--
REVIEWED $SHORT
VERDICT yes
-->")
# Only the last two lines count: an example trailer earlier is prose.
EXAMPLE_FIRST=$(code examplefirst "Пример: REVIEWED 0123456 / VERDICT yes
REVIEWED 0123456
VERDICT yes
Итог:
REVIEWED $SHORT
VERDICT no")
# An unclosed comment before the trailer cannot hide the verdict from the
# reader: the script writes it into the header, above the body.
UNCLOSED=$(code unclosed "<!-- без закрытия
REVIEWED $SHORT
VERDICT yes")
SEC_ECHOED=$(answer secechoed "REVIEWED $SHORT
SUMMARY critical=N high=N medium=N low=N")
SEC_DOTTED=$(answer secdotted "REVIEWED $SHORT
SUMMARY critical=0 high=1 medium=0 low=0.")
SEC_NOSUM=$(answer secnosum "Всё хорошо.
REVIEWED $SHORT")
SEC_PROSE=$(answer secprose "Critical: 0 | High: 0 | Medium: 0 | Low: 0
REVIEWED $SHORT")
SEC_OVERFLOW=$(answer secoverflow "REVIEWED $SHORT
SUMMARY critical=0 high=9223372036854775808 medium=0 low=0")
SEC_OVERFLOW2=$(answer secoverflow2 "REVIEWED $SHORT
SUMMARY critical=9223372036854775807 high=1 medium=0 low=0")
SEC_ZEROS=$(answer seczeros "REVIEWED $SHORT
SUMMARY critical=000 high=00 medium=5 low=0")
SPOOF=$(code spoof "# Cross-review · T-1 · code · codex
| verdict | ready to merge → exit 0 |
  | reviewed | $SHORT |
REVIEWED $SHORT
VERDICT no")

# 1. verdict → exit, both reviewers, report named <TASK>-<sha7>-<by>
run 0 codex-yes "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main
REP="$R/docs/reviews/T-1-$SHORT-codex.md"
[ -f "$REP" ] && ok || bad "codex report not at docs/reviews/T-1-$SHORT-codex.md"
grep -q 'model: stub-codex-1' "$REP" && ok || bad "report header lacks the model codex reported"
grep -q '^| verdict | ready to merge → exit 0 |$' "$REP" && ok || bad "report header lacks the verdict"
grep -q "^| reviewed | $SHORT |\$" "$REP" && ok || bad "report header lacks the reviewed sha"
grep -qE '^(REVIEWED|VERDICT) ' "$REP" && bad "the machine lines were left in the body (the header carries them)" || ok
grep -q '^\*\*Reasoning:\*\* ок$' "$REP" && ok || bad "the reviewer's prose is missing from the report"
[ "$OUT" = "docs/reviews/T-1-$SHORT-codex.md" ] && ok || bad "stdout is not the report path: $OUT"
run 0 claude-yes "STUB_ANSWER=$YES" -- --by claude --task T-1 --base main
[ -f "$R/docs/reviews/T-1-$SHORT-claude.md" ] && ok || bad "claude report missing"
run 1 with-fixes "STUB_ANSWER=$FIXES" -- --by codex --task T-1 --base main
run 1 not-ready "STUB_ANSWER=$NO" -- --by claude --task T-1 --base main
run 1 crlf-line-ends "STUB_ANSWER=$CRLF" -- --by codex --task T-1 --base main
run 1 example-trailer-earlier "STUB_ANSWER=$EXAMPLE_FIRST" -- --by codex --task T-1 --base main
run 0 unclosed-comment-before "STUB_ANSWER=$UNCLOSED" -- --by codex --task T-1 --base main
REP="$R/docs/reviews/T-1-$SHORT-codex.md"
[ "$(grep -n '^| verdict |' "$REP" | cut -d: -f1)" -lt "$(grep -n '^<!-- без закрытия' "$REP" | cut -d: -f1)" ] && ok || bad "the verdict header is not above the reviewer's body"
# 2. an answer the script cannot read is not clean
for kase in translated:TRANSLATED other-sha:OTHER_SHA no-reviewed-line:NO_SHA echoed-placeholder:ECHOED \
            longer-word:LONGER_WORD longer-sha:LONGER_SHA sha-then-list:SHA_LIST sha-then-suffix:SHA_SUFFIX \
            text-after-the-trailer:AFTER reversed-lines:REVERSED trailing-dot:DOTTED bold-trailer:BOLD \
            legacy-markdown-verdict:LEGACY indented-trailer:INDENTED fenced-trailer:FENCED commented-trailer:COMMENTED; do
  v="${kase#*:}"; f="${!v}"
  run 2 "${kase%%:*}" "STUB_ANSWER=$f" -- --by codex --task T-1 --base main
done
grep -q '^| verdict | unreadable' "$R/docs/reviews/T-1-$SHORT-codex.md" && ok || bad "an unreadable verdict is not recorded as unreadable in the report"
grep -q '^-->$' "$R/docs/reviews/T-1-$SHORT-codex.md" && ok || bad "an unreadable answer is not kept whole in the report"
# 3. security brief: the summary line decides
run 0 security-clean "STUB_ANSWER=$SEC_CLEAN" -- --by codex --task T-1 --base main --kind security
[ -f "$R/docs/reviews/T-1-$SHORT-codex-security.md" ] && ok || bad "security report not suffixed -security"
run 1 security-high "STUB_ANSWER=$SEC_HIGH" -- --by claude --task T-1 --base main --kind security
run 1 security-leading-zeros "STUB_ANSWER=$SEC_LEADING_ZERO" -- --by codex --task T-1 --base main --kind security
for kase in security-echoed:SEC_ECHOED security-trailing-dot:SEC_DOTTED security-no-summary:SEC_NOSUM security-prose-only:SEC_PROSE; do
  v="${kase#*:}"; f="${!v}"
  run 2 "${kase%%:*}" "STUB_ANSWER=$f" -- --by codex --task T-1 --base main --kind security
done
run 1 security-overflow-high "STUB_ANSWER=$SEC_OVERFLOW" -- --by codex --task T-1 --base main --kind security
run 1 security-overflow-sum "STUB_ANSWER=$SEC_OVERFLOW2" -- --by codex --task T-1 --base main --kind security
run 0 security-all-zero-digits "STUB_ANSWER=$SEC_ZEROS" -- --by codex --task T-1 --base main --kind security
# the body cannot present a second verdict: look-alike header rows are escaped
run 1 spoofed-header-in-body "STUB_ANSWER=$SPOOF" -- --by codex --task T-1 --base main
REP="$R/docs/reviews/T-1-$SHORT-codex.md"
[ "$(grep -c '^[[:space:]]*|[[:space:]]*verdict[[:space:]]*|' "$REP")" = 1 ] && ok || bad "the body carries a second, unescaped verdict row"
grep -q '^| verdict | not ready → exit 1 |$' "$REP" && ok || bad "the header verdict is not the machine verdict"
grep -qF '\| verdict | ready to merge → exit 0 |' "$REP" && ok || bad "the forged verdict row was dropped instead of escaped"
grep -qF '  \| reviewed |' "$REP" && ok || bad "an indented forged row was not escaped"
[ "$(grep -c '^# Cross-review' "$REP")" = 1 ] && ok || bad "the body carries a second report title"
run 2 code-verdict-for-security "STUB_ANSWER=$YES" -- --by codex --task T-1 --base main --kind security
run 2 security-summary-for-code "STUB_ANSWER=$SEC_CLEAN" -- --by codex --task T-1 --base main
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
for f in exec -s read-only --ignore-user-config --ignore-rules --ephemeral; do grep -qxF -- "$f" "$A" && ok || bad "codex argv lacks $f"; done
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
grep -A1 -xF -- --setting-sources "$A" | tail -n 1 | grep -qx '' && ok || bad "the isolated claude reviewer still loads a settings file (hooks, apiKeyHelper from the diff)"
grep -qxF '{"disableAllHooks":true}' "$A" && ok || bad "the isolated claude reviewer does not switch hooks off"
for f in -p --permission-mode dontAsk --tools Read,Grep,Glob --no-session-persistence --model opus \
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
code two "REVIEWED $TWO_SHA
VERDICT yes" > /dev/null
run 0 claude-fence "STUB_ANSWER=$TMP/two.md" -- --by claude --task T-1 --base main
grep -qE '^`{8,}text$' "$STUB_LOG/brief" && ok || bad "the material fence is not longer than the 7-backtick run inside it"
# 6b material leaves out the spec's own diff when the spec is in the range
git -C "$R" add docs/specs/T-1.spec.md; git -C "$R" commit -qm 'docs: spec'
SPEC_SHA=$(git -C "$R" rev-parse HEAD)
answer spec "REVIEWED $SPEC_SHA
SUMMARY critical=0 high=0 medium=0 low=0" > /dev/null
run 0 claude-security-spec "STUB_ANSWER=$TMP/spec.md" -- --by claude --task T-1 --base main --kind security
grep -q 'EDGE-MARKER-42' "$STUB_LOG/brief" && bad "the 6b material carries the spec's premortem edges through its diff" || ok
grep -q 'fence.md' "$STUB_LOG/brief" && ok || bad "the 6b material lost the rest of the diff"
git -C "$R" switch -q feature
git -C "$R" show two:docs/specs/T-1.spec.md > "$R/docs/specs/T-1.spec.md"   # committed on the side branch; untracked again here
grep -qxE '(Edit|Write|MultiEdit|NotebookEdit|Agent)' "$A" && bad "claude reviewer gets a write or dispatch tool" || ok
grep -A1 -xF -- --tools "$A" | tail -n 1 | grep -qE 'Edit|Write|Agent' && bad "--tools offers a write or dispatch tool" || ok
run 0 not-isolated "STUB_ANSWER=$YES" XREVIEW_ISOLATE=0 -- --by codex --task T-1 --base main
grep -qxF -- --ignore-user-config "$STUB_LOG/argv" && bad "XREVIEW_ISOLATE=0 still isolates" || ok
grep -qxF -- --ignore-rules "$STUB_LOG/argv" && ok || bad "XREVIEW_ISOLATE=0 lets .rules lift the codex reviewer out of read-only"
run 0 claude-not-isolated "STUB_ANSWER=$YES" XREVIEW_ISOLATE=0 -- --by claude --task T-1 --base main
A="$STUB_LOG/argv"
grep -A1 -xF -- --setting-sources "$A" | tail -n 1 | grep -qx 'user' && ok || bad "XREVIEW_ISOLATE=0 is not 'the user's own settings only' (project/local files come from the diff)"
grep -qxF -- --strict-mcp-config "$A" && ok || bad "XREVIEW_ISOLATE=0 lets MCP servers (write tools) back in"
git -C "$R" diff --quiet && ok || bad "the review modified a tracked file"

echo "tests/xreview${XREVIEW_TEST_AWK:+ (awk = $XREVIEW_TEST_AWK)}: $pass passed, $fail failed"
rc=0; [ "$fail" = 0 ] || rc=1
# The script runs on whatever awk the host has: the whole suite again under
# each other implementation present (a regex mawk cannot compile once took
# the script down outside its 0/1/2 contract).
if [ -z "${XREVIEW_TEST_AWK:-}" ]; then
  for impl in mawk busybox; do
    command -v "$impl" >/dev/null || { echo "tests/xreview: $impl not installed — that pass SKIPPED"; continue; }
    shim="$TMP/awk-$impl"; mkdir -p "$shim"
    if [ "$impl" = busybox ]; then printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$shim/awk"; else ln -s "$(command -v mawk)" "$shim/awk"; fi
    chmod +x "$shim/awk" 2>/dev/null || true   # lint: allow (a symlink keeps its target's mode)
    PATH="$shim:$PATH" XREVIEW_TEST_AWK="$impl" bash "$0" || rc=1
  done
fi
exit "$rc"
