#!/usr/bin/env bash
# xreview.sh — task-flow phase 6 / 6b review by the OTHER model: headless,
# read-only, briefed from the flow's artifacts only.
#
# Run it in place from the installed plugin — it fills the brief templates
# that ship next to it (skills/task/references/), so a copy in a repository
# goes stale with the first release:
#
#   bash "$ROOT/templates/xreview/xreview.sh" --by codex --task DEV-475 --base origin/develop
#   bash "$ROOT/templates/xreview/xreview.sh" --by claude --task DEV-475 --base origin/develop --kind security
#
# Exit codes (the verdict is read from the report, never assumed):
#   0  the review ran and its verdict is clean (code: "Ready to merge? Yes";
#      security: Critical 0 and High 0)
#   1  the review ran and its verdict blocks (code: "No" / "With fixes";
#      security: any Critical or High)
#   2  the review did not happen or cannot be read: empty range, no spec or no
#      DoD section, reviewer CLI missing or failed, verdict unreadable, or a
#      verdict attached to a different commit. Never read 2 as "clean".
set -euo pipefail

me=xreview
die() { printf '%s: %s\n' "$me" "$*" >&2; exit 2; }
usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Options:
  --by codex|claude     who reviews (the harness that did NOT write the diff)
  --task <TASK-ID>      ticket id; names the spec and the report
  --base <ref>          integration ref (fetch it first); the range is merge-base..head
  --head <ref>          revision under review (default HEAD)
  --kind code|security  phase 6 brief (default) or phase 6b brief
  --spec <path>         design spec (default docs/specs/<TASK-ID>.spec.md)
  --what-changed <file> factual summary for [WHAT_CHANGED] (default: commit subjects)
  --data-and-grants <file>  [DATA_AND_GRANTS] for --kind security
  --model <name>        reviewer model (no weaker than the session's)
  --effort <level>      reviewer reasoning effort
  --out-dir <dir>       report directory (default docs/reviews)
  --repo <dir>          repository (default: current directory)
  --brief-only          print the filled brief and exit 0 (no dispatch)
Environment:
  XREVIEW_ISOLATE=0     let the reviewer load the user's plugins and hooks
                        (memory plugins replay the author's session — default 1)
  XREVIEW_TIMEOUT=<s>   reviewer wall-clock limit (default 1800)
  XREVIEW_CODEX_PROFILE=<name>  add `-p <name>` to codex exec
  XREVIEW_KEEP_ENV='<VAR> …'    session-family variables to pass through anyway
  XREVIEW_ALLOW='<rule>;<rule>' extra --allowedTools rules for claude, e.g. 'Bash(make test)'
  XREVIEW_CODEX_BIN / XREVIEW_CLAUDE_BIN  CLI paths (default: codex / claude on PATH)
  XREVIEW_PROMPTS=<dir> brief templates (default: the plugin's skills/task/references)
EOF
}

BY="" TASK="" BASE_REF="" HEAD_REF="HEAD" KIND="code" SPEC="" WHAT="" DATA=""
MODEL="" EFFORT="" OUT_DIR="docs/reviews" REPO="." BRIEF_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --by) BY="${2:-}"; shift 2 ;;
    --task) TASK="${2:-}"; shift 2 ;;
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --head) HEAD_REF="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-}"; shift 2 ;;
    --spec) SPEC="${2:-}"; shift 2 ;;
    --what-changed) WHAT="${2:-}"; shift 2 ;;
    --data-and-grants) DATA="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --effort) EFFORT="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --brief-only) BRIEF_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

case "$BY" in codex|claude) ;; *) die "--by must be codex or claude" ;; esac
case "$KIND" in code|security) ;; *) die "--kind must be code or security" ;; esac
[ -n "$TASK" ] || die "--task is required"
[ -n "$BASE_REF" ] || die "--base is required (the integration ref, fetched: e.g. origin/develop)"
ISOLATE="${XREVIEW_ISOLATE:-1}"
TIMEOUT="${XREVIEW_TIMEOUT:-1800}"
case "$EFFORT" in ''|minimal|low|medium|high|xhigh|max) ;; *) die "--effort must be one of minimal low medium high xhigh max" ;; esac
case "$TIMEOUT" in ''|*[!0-9]*) die "XREVIEW_TIMEOUT must be whole seconds" ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
PROMPTS="${XREVIEW_PROMPTS:-$HERE/../../skills/task/references}"
TEMPLATE_FILE="$PROMPTS/code-review-prompt.md"
[ "$KIND" = security ] && TEMPLATE_FILE="$PROMPTS/security-review-prompt.md"
[ -r "$TEMPLATE_FILE" ] || die "brief template not readable: $TEMPLATE_FILE"

REPO_ROOT="$(git -C "$REPO" rev-parse --show-toplevel 2>&1)" || die "not a git repository: $REPO ($REPO_ROOT)"
cd "$REPO_ROOT"
HEAD_SHA="$(git rev-parse --verify --quiet "$HEAD_REF^{commit}")" || die "cannot resolve --head $HEAD_REF"
git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || die "cannot resolve --base $BASE_REF (fetch it first: git fetch --no-tags origin <branch>)"
BASE_SHA="$(git merge-base "$HEAD_SHA" "$BASE_REF")" || die "no merge base between $BASE_REF and $HEAD_REF"
rc=0; git diff --quiet "$BASE_SHA" "$HEAD_SHA" || rc=$?
case "$rc" in
  0) die "empty range $BASE_SHA..$HEAD_SHA — the review does not run (an empty diff reviews as 'no findings')" ;;
  1) ;;
  *) die "git diff failed on $BASE_SHA..$HEAD_SHA (rc $rc)" ;;
esac

[ -n "$SPEC" ] || SPEC="docs/specs/$TASK.spec.md"
[ -r "$SPEC" ] || die "spec not readable: $SPEC — the [DOD] slot is read from the spec file (design-spec-template: the file exists once a slot needs it); pass --spec"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/xreview.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SLOTS="$TMP/slots"; mkdir "$SLOTS"

# Sections are found by name, outside code fences; a section ends at the next
# level-2 heading.
section() {  # file, heading regex → section body
  awk -v re="$2" '
    /^(```|~~~)/ { fence = !fence }
    !fence && /^## / { if (on) exit; if ($0 ~ re) { on = 1; next } }
    on' "$1"
}
without_section() {  # file, heading regex → file minus that section
  awk -v re="$2" '
    /^(```|~~~)/ { fence = !fence }
    !fence && /^## / { skip = ($0 ~ re) }
    !skip' "$1"
}
DOD_RE='^## ([0-9]+[.] )?DoD'
EDGES_RE='^## ([0-9]+[.] )?Premortem edges'

section "$SPEC" "$DOD_RE" > "$SLOTS/DOD"
grep -q '[^[:space:]]' "$SLOTS/DOD" || die "$SPEC has no non-empty 'DoD → check table' section — nothing to grade the diff against"
without_section "$SPEC" "$EDGES_RE" > "$SLOTS/DESIGN_SPEC"
if [ "$KIND" = code ]; then
  section "$SPEC" "$EDGES_RE" > "$SLOTS/PREMORTEM_EDGES"
  grep -q '[^[:space:]]' "$SLOTS/PREMORTEM_EDGES" \
    || printf '(%s has no Premortem edges section — an absent section is itself worth a finding)\n' "$SPEC" > "$SLOTS/PREMORTEM_EDGES"
fi
if [ -n "$WHAT" ]; then
  [ -r "$WHAT" ] || die "--what-changed file not readable: $WHAT"
  cat "$WHAT" > "$SLOTS/WHAT_CHANGED"
else
  n="$(git rev-list --count --no-merges "$BASE_SHA..$HEAD_SHA")"
  git log --reverse --no-merges --format='- %s' "$BASE_SHA..$HEAD_SHA" | head -n 20 > "$SLOTS/WHAT_CHANGED"
  [ "$n" -le 20 ] || printf -- '- … and %s more commits\n' "$((n - 20))" >> "$SLOTS/WHAT_CHANGED"
fi
if [ "$KIND" = security ]; then
  if [ -n "$DATA" ]; then
    [ -r "$DATA" ] || die "--data-and-grants file not readable: $DATA"
    cat "$DATA" > "$SLOTS/DATA_AND_GRANTS"
  else
    printf 'not stated in this dispatch — derive it from the diff and the design-spec\n' > "$SLOTS/DATA_AND_GRANTS"
  fi
fi
printf '%s' "$BASE_SHA" > "$SLOTS/BASE_SHA"
printf '%s' "$HEAD_SHA" > "$SLOTS/HEAD_SHA"
printf '%s' "$HEAD_SHA" > "$SLOTS/SHA"

# The template is the 4-backtick block under "## Template".
awk '/^## Template/ { t = 1; next } t && /^````$/ { if (b) exit; b = 1; next } b' "$TEMPLATE_FILE" > "$TMP/template"
[ -s "$TMP/template" ] || die "no '## Template' block in $TEMPLATE_FILE"
grep -qE '\[(WHAT_CHANGED|DOD|DESIGN_SPEC|BASE_SHA|HEAD_SHA)\]' "$TMP/template" \
  || die "template $TEMPLATE_FILE carries none of the slots — refusing to dispatch an unfilled contract"

# One pass, literal: a slot value is inserted verbatim and never rescanned, so
# '&', '\' or a '[HEAD_SHA]' inside the spec stays text.
awk -v dir="$SLOTS" '
  function slurp(name,   f, line, s, n, r) {
    f = dir "/" name; s = ""; n = 0
    while ((r = (getline line < f)) > 0) { s = s (n++ ? "\n" : "") line }
    close(f)
    if (r < 0 && n == 0) return "\001"
    return s
  }
  BEGIN {
    k = split("WHAT_CHANGED DOD DESIGN_SPEC PREMORTEM_EDGES DATA_AND_GRANTS BASE_SHA HEAD_SHA SHA", names, " ")
    for (i = 1; i <= k; i++) { v = slurp(names[i]); if (v != "\001") val[names[i]] = v }
  }
  {
    out = ""; rest = $0
    while (match(rest, /\[[A-Z_]+\]/)) {
      tok = substr(rest, RSTART + 1, RLENGTH - 2)
      out = out substr(rest, 1, RSTART - 1) ((tok in val) ? val[tok] : substr(rest, RSTART, RLENGTH))
      rest = substr(rest, RSTART + RLENGTH)
    }
    print out rest
  }' "$TMP/template" > "$TMP/brief"

if [ "$BRIEF_ONLY" = 1 ]; then cat "$TMP/brief"; exit 0; fi

# The reviewer inherits no session identity: a nested harness otherwise sees
# the author's session ids, plugin paths and the parent's messaging channel.
# Removed by family, so a variable a newer harness adds is covered too; kept:
# the variables that select or carry the reviewer's own authentication, and
# whatever XREVIEW_KEEP_ENV names.
SCRUB=()
while IFS= read -r v; do
  case " ${XREVIEW_KEEP_ENV:-} " in *" $v "*) continue ;; esac
  case "$v" in
    CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_*|CLAUDE_CODE_SKIP_*_AUTH|CLAUDE_CODE_CLIENT_*) continue ;;
    CLAUDECODE|CLAUDE_CODE_*|CLAUDE_PLUGIN_*|CLAUDE_ENV_FILE|CLAUDE_PROJECT_DIR|CLAUDE_EFFORT|CLAUDE_PID) SCRUB+=(-u "$v") ;;
    CODEX_SESSION_ID|CODEX_THREAD_ID|CODEX_CI|CODEX_SANDBOX*|PLUGIN_ROOT|PLUGIN_DATA|PP_*|PREDICT) SCRUB+=(-u "$v") ;;
  esac
done < <(compgen -e)
TO=(); command -v timeout >/dev/null && TO=(timeout "$TIMEOUT")
SEEN_MODEL="${MODEL:-default}"
ISOLATION="off (XREVIEW_ISOLATE=0)"

if [ "$BY" = codex ]; then
  BIN="${XREVIEW_CODEX_BIN:-codex}"
  command -v "$BIN" >/dev/null || die "reviewer CLI not found: $BIN (install Codex CLI, or review with --by claude)"
  ARGS=(exec -s read-only -C "$REPO_ROOT" --ephemeral --color never -o "$TMP/last.md")
  if [ "$ISOLATE" = 1 ]; then ARGS+=(--ignore-user-config); ISOLATION="on (--ignore-user-config)"; fi
  [ -z "${XREVIEW_CODEX_PROFILE:-}" ] || ARGS+=(-p "$XREVIEW_CODEX_PROFILE")
  [ -z "$MODEL" ] || ARGS+=(-m "$MODEL")
  [ -z "$EFFORT" ] || ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")
  ARGS+=(-)
else
  BIN="${XREVIEW_CLAUDE_BIN:-claude}"
  command -v "$BIN" >/dev/null || die "reviewer CLI not found: $BIN (install Claude Code, or review with --by codex)"
  ALLOW=(Read Grep Glob "Bash(git diff *)" "Bash(git show *)" "Bash(git log *)" "Bash(git grep *)"
    "Bash(git status *)" "Bash(git status)" "Bash(git rev-parse *)" "Bash(git ls-files *)"
    "Bash(git blame *)" "Bash(git merge-base *)" "Bash(git cat-file *)")
  if [ -n "${XREVIEW_ALLOW:-}" ]; then
    IFS=';' read -r -a EXTRA <<< "$XREVIEW_ALLOW"
    ALLOW+=(${EXTRA[@]+"${EXTRA[@]}"})
  fi
  # Isolation also drops the user's language setting; the brief's own
  # "respond in Russian" is restated where -p weighs it.
  ARGS=(-p --output-format text --no-session-persistence --tools "Read,Grep,Glob,Bash"
    --permission-mode dontAsk --append-system-prompt
    "Write the review in Russian, as the brief's Output format says. Keep code, paths, identifiers and the English Assessment/Summary label lines exactly as the brief shows them.")
  if [ "$ISOLATE" = 1 ]; then ARGS+=(--setting-sources project,local); ISOLATION="on (--setting-sources project,local)"; fi
  [ -z "$MODEL" ] || ARGS+=(--model "$MODEL")
  [ -z "$EFFORT" ] || ARGS+=(--effort "$EFFORT")
  ARGS+=(--allowedTools "${ALLOW[@]}")
fi

printf '%s: %s reviews %s..%s (%s brief, isolation %s)\n' "$me" "$BY" "${BASE_SHA:0:7}" "${HEAD_SHA:0:7}" "$KIND" "$ISOLATION" >&2
rrc=0
if [ "$BY" = codex ]; then
  env ${SCRUB[@]+"${SCRUB[@]}"} ${TO[@]+"${TO[@]}"} "$BIN" "${ARGS[@]}" < "$TMP/brief" > "$TMP/stdout" 2> "$TMP/stderr" || rrc=$?
  m="$(sed -nE 's/^model: ([^[:space:]]+).*/\1/p' "$TMP/stderr" | head -n 1)"
  [ -z "$m" ] || SEEN_MODEL="$m"
else
  env ${SCRUB[@]+"${SCRUB[@]}"} ${TO[@]+"${TO[@]}"} "$BIN" "${ARGS[@]}" < "$TMP/brief" > "$TMP/last.md" 2> "$TMP/stderr" || rrc=$?
fi
if [ "$rrc" != 0 ] || [ ! -s "$TMP/last.md" ]; then
  printf '%s: reviewer %s exited %s%s — no review happened. Last stderr lines:\n' "$me" "$BIN" "$rrc" \
    "$([ -s "$TMP/last.md" ] || printf ' with no final message')" >&2
  tail -n 20 "$TMP/stderr" >&2
  exit 2
fi

# Verdict. A verdict attaches to the commit it saw. Parsing is strict: every
# field must be the whole value on its line and agree with itself — an echoed
# placeholder, a longer word or a longer sha is "unreadable", never clean.
verdict="unreadable"; out=2; why=""
shas="$(awk '{
  line = $0
  while ((i = index(line, "Reviewed:")) > 0) {
    rest = substr(line, i + 9); sub(/^[*` \t]*/, "", rest)
    if (match(rest, /^[0-9a-f]+/) && substr(rest, RLENGTH + 1, 1) !~ /[0-9A-Za-z_]/) print substr(rest, 1, RLENGTH)
    else print "BAD"
    line = substr(line, i + 9)
  }
}' "$TMP/last.md" | sort -u)"
nshas="$(printf '%s' "$shas" | grep -c . || true)"  # lint: allow (an empty list counts as 0)
if [ "$nshas" = 0 ]; then
  why="no 'Reviewed: <sha>' line"
elif [ "$nshas" != 1 ] || [ "$shas" = BAD ]; then
  why="the 'Reviewed:' field is not one clean sha ($(printf '%s' "$shas" | tr '\n' ' '))"
elif [ "${#shas}" -lt 7 ] || [ "${#shas}" -gt 40 ] || [ "${HEAD_SHA#"$shas"}" = "$HEAD_SHA" ]; then
  why="the report says Reviewed: $shas, the range head is $HEAD_SHA"
elif [ "$KIND" = code ]; then
  vals="$(awk '{
    line = $0; i = index(line, "Ready to merge?"); if (!i) next
    v = substr(line, i + 15); sub(/^[* \t]*/, "", v); sub(/[*. \t]*$/, "", v)
    print tolower(v)
  }' "$TMP/last.md" | sort -u)"
  case "$vals" in
    yes) verdict="ready to merge"; out=0 ;;
    no) verdict="not ready"; out=1 ;;
    "with fixes") verdict="ready with fixes"; out=1 ;;
    "") why="no 'Ready to merge? Yes|No|With fixes' line" ;;
    *) why="the verdict line is not exactly Yes, No or With fixes ($(printf '%s' "$vals" | tr '\n' '/'))" ;;
  esac
else
  sums="$(tr -d '*' < "$TMP/last.md" | sed -nE 's/^[[:space:]]*Critical:[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*High:[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*Medium:[[:space:]]*[0-9]+[[:space:]]*\|[[:space:]]*Low:[[:space:]]*[0-9]+[[:space:]]*$/\1 \2/p' | sort -u)"
  case "$(printf '%s' "$sums" | grep -c . || true)" in  # lint: allow (an empty list counts as 0)
    1) c="${sums% *}"; h="${sums#* }"
       if [ $((c + h)) -gt 0 ]; then verdict="Critical $c / High $h"; out=1; else verdict="Critical 0 / High 0"; out=0; fi ;;
    0) why="no 'Critical: N | High: N | Medium: N | Low: N' summary line" ;;
    *) why="summary lines disagree ($(printf '%s' "$sums" | tr '\n' '/'))" ;;
  esac
fi
[ "$out" != 2 ] || verdict="unreadable: $why"

SAFE_TASK="$(printf '%s' "$TASK" | tr -c 'A-Za-z0-9._-' '_')"
SUFFIX=""; [ "$KIND" = security ] && SUFFIX="-security"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/$SAFE_TASK-${HEAD_SHA:0:7}-$BY$SUFFIX.md"
if command -v sha256sum >/dev/null; then BRIEF_SUM="$(sha256sum "$TMP/brief" | cut -d' ' -f1)"
else BRIEF_SUM="$(shasum -a 256 "$TMP/brief" | cut -d' ' -f1)"; fi
{
  printf '<!-- generated by task-flow templates/xreview/xreview.sh; the reviewer wrote everything below the rule -->\n'
  printf '# Cross-review · %s · %s · %s\n\n' "$TASK" "$KIND" "$BY"
  printf '| field | value |\n|---|---|\n'
  printf '| reviewer | %s (model: %s) |\n' "$BY" "$SEEN_MODEL"
  printf '| range | %s..%s (base %s) |\n' "$BASE_SHA" "$HEAD_SHA" "$BASE_REF"
  printf '| brief | %s, sha256 %s |\n' "$(basename "$TEMPLATE_FILE")" "$BRIEF_SUM"
  printf '| isolation | %s |\n' "$ISOLATION"
  printf '| verdict | %s → exit %s |\n' "$verdict" "$out"
  printf '| date | %s |\n\n---\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat "$TMP/last.md"
} > "$REPORT"
printf '%s: %s → exit %s · report %s\n' "$me" "$verdict" "$out" "$REPORT" >&2
printf '%s\n' "$REPORT"
exit "$out"
