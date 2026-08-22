#!/usr/bin/env bash
# lint.sh — Tier-1 repository invariants: deterministic, no LLM, <2 s.
#
# This repo ships Markdown and a bash payload, so its "tests" are the written
# rules in CLAUDE.md turned into greps. Each check names the rule it guards.
# Exit 1 on any violation. Check 3 (fail-closed payload) covers only
# templates/ci-gate/ci/*.sh; `# lint: allow` on a payload line exempts it.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
err() { printf 'lint: %s\n' "$*" >&2; fail=1; }

# 1. Every references/<file>.md a SKILL.md names exists — a missing reference
#    degrades silently into invention (premortem H-001).
for s in skills/*/; do
  s="${s%/}"; [ -f "$s/SKILL.md" ] || continue
  for f in $(grep -oE 'references/[a-z0-9-]+\.md' "$s/SKILL.md" | sed 's|references/||' | sort -u); do
    [ -f "$s/references/$f" ] || err "$s/SKILL.md names missing reference $f"
  done
done

# 2. A skill with references/ resolves $ROOT via CLAUDE_PLUGIN_ROOT once; no
#    skill hardcodes a ~/.claude path (except to forbid it).
for s in skills/*/; do
  s="${s%/}"; [ -d "$s/references" ] || continue
  grep -q 'CLAUDE_PLUGIN_ROOT' "$s/SKILL.md" || err "$s/SKILL.md has references/ but no CLAUDE_PLUGIN_ROOT resolution block"
done
if grep -rn '~/\.claude' skills/ | grep -v 'never' >/dev/null; then
  err "hardcoded ~/.claude path in skills/ (only a 'never …' mention is allowed)"
  grep -rn '~/\.claude' skills/ | grep -v 'never' >&2
fi

# 3. Payload fails closed: no '|| true' / '2>/dev/null' on a verdict-bearing line.
if grep -nE '\|\| true|2>/dev/null' templates/ci-gate/ci/*.sh | grep -v 'lint: allow' >/dev/null; then
  err "fail-open idiom in templates/ci-gate/ci (mark a deliberate one with '# lint: allow')"
  grep -nE '\|\| true|2>/dev/null' templates/ci-gate/ci/*.sh | grep -v 'lint: allow' >&2
fi

# 4. Payload parses; manifest is JSON; payload scripts are executable.
for f in templates/ci-gate/ci/*.sh; do
  bash -n "$f" || err "syntax error: $f"
  [ -x "$f" ] || err "not executable: $f"
done
jq -e . .claude-plugin/plugin.json >/dev/null || err ".claude-plugin/plugin.json is not valid JSON"

# 5. Axioms as text invariants (CLAUDE.md → "The central axiom", "Clean-context
#    dispatch"). Two rules learned the hard way: greps are whitespace-tolerant
#    (a rewrap must not drop an axiom silently) and they are **scoped to the
#    section that must carry the rule** and pinned to the load-bearing wording —
#    a token that also appears elsewhere in the file protects nothing.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
section() {  # file, awk range → the section as one line
  awk "$2" "$1" | tr '\n' ' ' | tr -s ' '
}
P8=$(section skills/task/SKILL.md '/^## 8\. Close/,/^## Fixed discipline/')
P6=$(section skills/task/SKILL.md '/^## 6\. Code-review/,/^## 6b\./')
[ -n "$P8" ] && [ -n "$P6" ] || err "task/SKILL.md: phase 6 or phase 8 section not found — the axiom checks below are blind"
printf '%s' "$P8" | grep -q 'deterministic gate' || err "task phase 8 lost the 'deterministic gate' clause"
printf '%s' "$P8" | grep -q 'present and passed' || err "task phase 8 lost the 'green means the gate jobs are present and passed' rule"
printf '%s' "$P8" | grep -q "repo's own gate" || err "task phase 8 no longer reads the gate jobs from the repo's own CI file"
printf '%s' "$P6" | grep -q 'never the session transcript' || err "task phase 6 lost the clean-context clause"
printf '%s' "$P6" | grep -qi 'read-only' || err "task phase 6 lost the read-only rule for the reviewer"
flat skills/decompose/SKILL.md | grep -q 'fresh context' || err "decompose phase 5 lost the fresh-context clause"
grep -q 'factual' skills/task/references/code-review-prompt.md || err "code-review-prompt lost the 'WHAT_CHANGED is factual' rule"
# The orchestrator's half of the review contract lives in the template now: pin
# the section and each rule it carries, not the words that also appear in prose.
CR=skills/task/references/code-review-prompt.md
grep -q '^## After the review comes back' "$CR" || err "$CR lost the orchestrator section (severity, termination, verdict sha)"
flat "$CR" | grep -q 'Severity maps to action' || err "$CR lost 'severity maps to action'"
flat "$CR" | grep -q 'behavioural' || err "$CR lost the behavioural/description split that terminates the loop"
flat "$CR" | grep -q 'fix(review):' || err "$CR lost the one-commit-per-fix rule"
flat "$CR" | grep -q 'A verdict attaches to the commit it saw' || err "$CR lost 'a verdict attaches to the commit it saw'"

# 6. decompose vocabulary is a cross-file contract: 6 author fields, 4 dod members, 8 checks.
for f in skills/decompose/SKILL.md skills/decompose/references/task-schema.md \
         skills/decompose/references/qa-checklist.md skills/decompose/references/draft-template.md \
         skills/decompose/references/tracker-sync.md; do
  for w in name context requirements dod story_points depends_on truths acceptance_criteria verify; do
    grep -qE "(^|[^A-Za-z_])${w}([^A-Za-z_]|$)" "$f" || err "$f lacks the field token '$w'"
  done
done
tr '\n' ' ' < skills/decompose/SKILL.md | grep -q 'the 8 checks' || err "decompose SKILL.md no longer says 'the 8 checks'"
grep -q 'The 8 checks' skills/decompose/references/qa-checklist.md || err "qa-checklist.md check count drifted"
# 1.10.0 — decompose contracts that must not shrink back. Each is pinned to the
# section, table row or code block that carries it AND to its load-bearing
# phrase, read flattened (a rewrap must not drop a rule silently); a loose word
# elsewhere in the file is not proof the rule is still there.
QA=skills/decompose/references/qa-checklist.md
[ "$(grep -cE '^### Check [0-9]+ ' "$QA")" -eq 8 ] || err "$QA: the number of '### Check N' sections is not 8"
grep -q '^### Check 2 — Field completeness and quality' "$QA" || err "$QA: Check 2 lost its quality half"
C1=$(section "$QA" '/^### Check 1 /,/^### Check 2 /')
printf '%s' "$C1" | grep -q 'report it as an uncovered requirement with `task: null`' || err "$QA: Check 1 no longer turns a silently cut input fragment into a BLOCKER"
C2=$(section "$QA" '/^### Check 2 /,/^### Check 3 /')
printf '%s' "$C2" | grep -q 'Invented identifiers are a BLOCKER' || err "$QA: Check 2 lost the invented-identifier rule"
printf '%s' "$C2" | grep -q '<placeholder: what it is>' || err "$QA: Check 2 lost the <placeholder: …> form"
printf '%s' "$C2" | grep -q 'test -e <path>' || err "$QA: Check 2 lost the @-reference check command"
printf '%s' "$C2" | grep -q 'An identifier the task \*creates\*' || err "$QA: Check 2 no longer distinguishes an identifier the task creates from an invented one"
C5=$(section "$QA" '/^### Check 5 /,/^### Check 6 /')
printf '%s' "$C5" | grep -q 'The contract has to match' || err "$QA: Check 5 lost the producer→consumer contract rule"
printf '%s' "$C5" | grep -q 'and \*\*BLOCKER\*\* when the producer' || err "$QA: Check 5's severity line lost the contract-mismatch BLOCKER"
C6=$(section "$QA" '/^### Check 6 /,/^### Check 7 /')
printf '%s' "$C6" | grep -q 'form from Check 2 is \*\*not\*\* a hit here' || err "$QA: Check 6 no longer exempts the <placeholder: …> form — Check 2 and Check 6 contradict"
printf '%s' "$C6" | grep -q 'forged owner — \*\*BLOCKER\*\*' || err "$QA: Check 6 no longer verifies the 'Not in this task:' owner as a BLOCKER"
OC=$(section "$QA" '/^## Output contract/,/^## Revision loop/')
for s in requirement-coverage field-completeness graph-acyclicity atomicity key-links scope-reduction mece wave-parallelism; do
  printf '%s' "$OC" | grep -q "\`$s\`" || err "$QA: the output contract lost the check slug '$s'"
done
printf '%s' "$OC" | grep -q 'repeat: true' || err "$QA: the output contract lost the repeat flag"
RL=$(section "$QA" '/^## Revision loop/,0')
printf '%s' "$RL" | grep -q 'Convergence guard' || err "$QA: revision loop lost the convergence guard"
printf '%s' "$RL" | grep -q 'When every BLOCKER of a check-run is a repeat' || err "$QA: the convergence guard lost its trigger (every BLOCKER a repeat)"
printf '%s' "$RL" | grep -q 'stops and escalates to the user' || err "$QA: the convergence guard no longer escalates"
printf '%s' "$RL" | grep -q '`PASSED` still requires a clean check-run' || err "$QA: the convergence guard no longer says PASSED still needs a clean run"
printf '%s' "$RL" | grep -q 'or the convergence guard firing earlier' || err "$QA: the escalation shape is not tied to the convergence guard"
DT=skills/decompose/references/draft-template.md
grep -q '^## Out of scope' "$DT" || err "$DT lost the Out of scope table"
grep -q '^| From the input | Decision | Why |' "$DT" || err "$DT: the Out of scope table lost its columns"
grep -q '^## Placeholders' "$DT" || err "$DT lost the Placeholders table"
grep -q '^| Placeholder | Stands for | Carried by | Confirmed by |' "$DT" || err "$DT: the Placeholders table lost its columns"
grep -q '^\*\*Checked against:\*\*' "$DT" || err "$DT: the header lost the 'Checked against:' line"
HT=$(section "$DT" '/^## How to fill this in/,/^````markdown/')
printf '%s' "$HT" | grep -q 'Fill \*\*Out of scope\*\*' || err "$DT: the how-to list no longer fills Out of scope / Placeholders"
TS=skills/decompose/references/task-schema.md
grep -E '^\| \*\*context\*\* \|' "$TS" | grep -q 'Not in this task: <what> — <TASK-ID> owns it' || err "$TS: the context row lost the 'Not in this task:' advisory line"
grep -E '^\| \*\*context\*\* \|' "$TS" | grep -q 'risk tier: T1' || err "$TS: the context row lost the 'risk tier:' advisory line"
PH=$(section "$TS" '/^## Identifiers you could not confirm/,/^## `dod`/')
printf '%s' "$PH" | grep -q '<placeholder: what it is>' || err "$TS: the placeholder section lost the form"
printf '%s' "$PH" | grep -q 'never as a plausible name' || err "$TS: the placeholder section lost the rule"
EP=skills/decompose/references/edge-probe.md
for r in 'authorization | actor-facing' 'surface states | ui' 'interaction | ui' 'grants | infra' 'secrets | infra' 'environments | infra'; do
  grep -qE "^\| $r \| .{30,} \|$" "$EP" || err "$EP: lost the surface row '$r' (or its probe question)"
done
RF=$(section "$EP" '/^## Relevance filter first/,/^## The eight/')
for w in 'actor-facing' '`ui`' '`infra`'; do
  printf '%s' "$RF" | grep -q "$w" || err "$EP: the relevance filter never assigns the surface $w — its rows can never be raised"
done
TR=skills/decompose/references/tracker-sync.md
CB=$(awk '/^## 1\. Adapter contract/,/^## 2\./' "$TR" | awk '/^```/{f=!f;next} f')
for op in create_issue update_issue link read_issue search_issues describe_project; do
  printf '%s\n' "$CB" | grep -q "^$op(" || err "$TR: the adapter contract block lost $op"
done
for m in markdown jira-wiki adf-via-markdown plain; do
  printf '%s\n' "$CB" | grep -E '^markup:' | grep -q "\"$m\"" || err "$TR: the contract block's markup line lost '$m'"
done
grep -q 'through two operations' "$TR" && err "$TR §1 still says 'two operations' — the contract has a read and a search now"
P3=$(section "$TR" '/^## 3\. Runtime tool discovery/,/^## 4\./')
printf '%s' "$P3" | grep -q 'names a REST endpoint' || err "$TR §3 lost the REST transport"
printf '%s' "$P3" | grep -q 'never echoed' || err "$TR §3 lost the token hygiene for the REST transport"
P5=$(section "$TR" '/^## 5\. Dry-run mode/,/^## 6\./')
printf '%s' "$P5" | grep -q 'Possible duplicates' || err "$TR §5 lost the possible-duplicates block"
printf '%s' "$P5" | grep -q 'The preflight summary first' || err "$TR §5: the dry-run no longer prints the preflight summary"
printf '%s' "$P5" | grep -q 'idempotency: unavailable' || err "$TR §5: the dry-run no longer warns that a re-run without a search is not idempotent"
P6=$(section "$TR" '/^## 6\. Stable idempotency key/,/^## 7\./')
printf '%s' "$P6" | grep -q 'a re-run is then \*\*not\*\* idempotent' || err "$TR §6 no longer admits that a re-run without a search is not idempotent"
printf '%s' "$P6" | grep -q 'exact key line' || err "$TR §6: a fuzzy search hit may pass as a key match again"
for r in 'read_issue(<TASK-ID>)' 'search_issues(query)' 'markup' 'update_issue(<TASK-ID>, …)'; do
  grep -q "^| \`$r\` |" "$TR" || err "$TR §7: the YouTrack illustration has no row for $r"
done
grep -E '^\| `context` \+ `requirements`' "$TR" | grep -q 'Source: <draft path>, epic <ID or none>' || err "$TR §7: the description mapping lost the Source: line"
P8=$(section "$TR" '/^## 8\. Partial-failure/,/^## 9\./')
printf '%s' "$P8" | grep -qE 'read-back: [0-9]+ match / [0-9]+ mismatch' || err "$TR §8 lost the read-back mismatch report shape"
P9=$(section "$TR" '/^## 9\. Procedure/,/^## 10\./')
printf '%s' "$P9" | grep -q 'Preflight — one read before any promise' || err "$TR §9 lost the preflight step"
printf '%s' "$P9" | grep -q 'Read back what you wrote' || err "$TR §9 lost the read-back step"
printf '%s' "$P9" | grep -q 'shown, not declared' || err "$TR §9: the read-back no longer has to show sent and read values"
printf '%s' "$P9" | grep -q '`estimate` numerically equal' || err "$TR §9 lost the read-back predicate"
printf '%s' "$P9" | grep -q 'never as a match' || err "$TR §9: an unreadable field may pass as a match again"
printf '%s' "$P9" | grep -q 'line is never rewritten' || err "$TR §9: the id-rewrite pass may clobber the idempotency key again"
P10=$(section "$TR" '/^## 10\. Return/,0')
printf '%s' "$P10" | grep -q 'with their URLs' || err "$TR §10 no longer returns URLs next to ids"
DS=skills/decompose/SKILL.md
D0=$(section "$DS" '/^## 0\. Ingest/,/^## 1\. /')
printf '%s' "$D0" | grep -q 'Read the code before the first question' || err "$DS phase 0 lost 'read the code before the first question'"
printf '%s' "$D0" | grep -q 'recall, not authority' || err "$DS phase 0 lost 'memory is recall, not authority'"
D1=$(section "$DS" '/^## 1\. Requirements/,/^## 2\. /')
printf '%s' "$D1" | grep -q 'a fragment in neither list was cut' || err "$DS phase 1 no longer writes the out-of-scope list next to the requirements"
D3=$(section "$DS" '/^## 3\. Enrich/,/^## 4\. /')
printf '%s' "$D3" | grep -q 'Never invent an identifier' || err "$DS phase 3 lost the placeholder rule"
D5=$(section "$DS" '/^## 5\. QA/,/^## 6\. /')
printf '%s' "$D5" | grep -q 'the repository path' || err "$DS phase 5 no longer hands the checker the repository path — Check 2 cannot run test -e/grep"
printf '%s' "$D5" | grep -q 'out-of-scope list from Phase 1' || err "$DS phase 5 no longer hands the checker the out-of-scope list"
printf '%s' "$D5" | grep -q 'BLOCKERs are all repeats' || err "$DS phase 5 does not escalate on the convergence guard"
D6=$(section "$DS" '/^## 6\. Draft/,/^## 7\. /')
printf '%s' "$D6" | grep -q "out-of-scope\*\* table (Phase 1's list, rendered)" || err "$DS phase 6 no longer renders Phase 1's out-of-scope list"
printf '%s' "$D6" | grep -q 'out of dispatch until' || err "$DS phase 6 no longer keeps a placeholder-carrying task out of dispatch"
D7=$(section "$DS" '/^## 7\. Tracker sync/,/^## Handoff/')
printf '%s' "$D7" | grep -q 'preflight first' || err "$DS phase 7 lost the preflight"
printf '%s' "$D7" | grep -q 'read every touched issue back' || err "$DS phase 7 lost the read-back"
printf '%s' "$D7" | grep -q 'with their URLs' || err "$DS phase 7 no longer returns URLs"
flat skills/task/SKILL.md | grep -q '`Not in this task:` line from the same source' || err "task/SKILL.md phase 0 no longer consumes the decompose 'Not in this task:' line"
flat README.md | grep -q 'reads every issue back' || err "README.md: the decompose paragraph no longer says the push reads every issue back"
flat README.ru.md | grep -q 'перечитывает каждую затронутую задачу' || err "README.ru.md: the decompose paragraph no longer says the push reads every issue back"

# 7. No personal absolute paths in tracked files (CLAUDE.md is local and untracked).
if git grep -nE '/home/[a-z]+/' -- . ':!CLAUDE.md' >/dev/null; then
  err "personal absolute path in tracked files:"
  git grep -nE '/home/[a-z]+/' -- . ':!CLAUDE.md' >&2
fi

# 8. One scanner version in every path: fetch pin == pre-commit rev comment ==
#    CI image tag, and ONE digest everywhere it appears (a consistent wrong
#    digest still passes — correctness is the human's job at bump time).
V=$(sed -nE 's/^PIN_VERSION="([0-9.]+)"/\1/p' templates/ci-gate/ci/gitleaks-fetch.sh)
[ -n "$V" ] || err "cannot read PIN_VERSION from gitleaks-fetch.sh"
V_RE=${V//./\\.}
grep -qE "^\s+rev: [0-9a-f]{40}\s+# v$V_RE\$" templates/ci-gate/.pre-commit-config.yaml \
  || err ".pre-commit-config.yaml: gitleaks rev must be a commit SHA tagged '# v$V'"
IMAGE_FILES="templates/ci-gate/gitlab/ci-gate.gitlab-ci.yml templates/ci-gate/gitlab/ci-gate.shell.gitlab-ci.yml templates/ci-gate/github/gate.yml .github/workflows/check.yml"
for f in $IMAGE_FILES; do
  grep -qE "gitleaks:v$V_RE@sha256:[0-9a-f]{64}" "$f" || err "$f: gitleaks image not pinned to v$V by digest"
done
# shellcheck disable=SC2086
DIGESTS=$(grep -ohE "gitleaks:v$V_RE@sha256:[0-9a-f]{64}" $IMAGE_FILES | sort -u | wc -l)
[ "$((DIGESTS))" -eq 1 ] || err "gitleaks image digest differs between CI files ($DIGESTS distinct values)"
if grep -nE 'image:.*:latest|gitleaks:latest' templates/ci-gate/gitlab/*.yml templates/ci-gate/github/*.yml >/dev/null; then
  err "':latest' image tag in a CI template:"
  grep -nE 'image:.*:latest|gitleaks:latest' templates/ci-gate/gitlab/*.yml templates/ci-gate/github/*.yml >&2
fi
if grep -nE 'uses: [^@]+@v[0-9]' templates/ci-gate/github/gate.yml .github/workflows/check.yml >/dev/null; then
  err "an action is pinned by tag, not commit SHA:"
  grep -nE 'uses: [^@]+@v[0-9]' templates/ci-gate/github/gate.yml .github/workflows/check.yml >&2
fi
if grep -q 'autoupdate' templates/ci-gate/.pre-commit-config.yaml && ! grep -q 'Never `pre-commit autoupdate`' templates/ci-gate/.pre-commit-config.yaml; then
  err ".pre-commit-config.yaml recommends autoupdate"
fi
grep -q 'regexTarget = "line"' templates/ci-gate/.gitleaks.toml && err '.gitleaks.toml: regexTarget = "line" lets a placeholder excuse a real secret on the same line'

# 9. The payload is one set: every ci/*.sh and CODEOWNERS the payload ships is
#    named in the ci-gate SKILL.md copy step and in ci/README.md; the three CI
#    templates define the same gate jobs; the pre-commit config carries every
#    local guard; the gitleaks-backed scripts resolve the scanner the same way.
# The skill copies ci/ as a directory (a per-file list drifts the moment a
# script is added); ci/README.md is where each script is documented.
grep -q 'the whole `ci/` directory' skills/ci-gate/SKILL.md || err "skills/ci-gate/SKILL.md must tell the agent to copy the whole ci/ directory, not a file list"
for f in templates/ci-gate/ci/*.sh; do
  b=$(basename "$f")
  grep -q "$b" templates/ci-gate/ci/README.md || err "templates/ci-gate/ci/README.md does not document payload script $b"
done
for f in .gitleaks.toml .pre-commit-config.yaml CODEOWNERS; do
  grep -q "$f" skills/ci-gate/SKILL.md || err "skills/ci-gate/SKILL.md does not name payload root file $f"
done
for job in secret-scan migration-guard unicode-guard; do
  for f in templates/ci-gate/gitlab/ci-gate.gitlab-ci.yml templates/ci-gate/gitlab/ci-gate.shell.gitlab-ci.yml templates/ci-gate/github/gate.yml; do
    grep -qE "^\s*${job}:" "$f" || err "$f lacks the '$job' job"
  done
  grep -q "$job" templates/ci-gate/ci/README.md || err "ci/README.md does not mention the '$job' job"
done
for h in migration-guard.sh unicode-guard.sh pre-push.sh; do
  grep -q "ci/$h" templates/ci-gate/.pre-commit-config.yaml || err ".pre-commit-config.yaml lacks a hook for ci/$h"
done
grep -q 'stages: \[pre-push\]' templates/ci-gate/.pre-commit-config.yaml || err ".pre-commit-config.yaml: pre-push hook must be staged 'pre-push'"
grep -q '^default_stages: \[pre-commit\]' templates/ci-gate/.pre-commit-config.yaml || err ".pre-commit-config.yaml: default_stages must pin the other hooks to pre-commit"
# One scanner resolution, in one file: three inline copies drifted apart once.
grep -q 'GATE_PINNED_ONLY' templates/ci-gate/ci/gitleaks-bin.sh || err "gitleaks-bin.sh no longer honours GATE_PINNED_ONLY"
for f in templates/ci-gate/ci/gate.sh templates/ci-gate/ci/scan-text.sh templates/ci-gate/ci/pre-push.sh; do
  grep -q 'gitleaks-bin.sh' "$f" || err "$f must resolve the scanner through ci/gitleaks-bin.sh"
  grep -qE '(^|[^-])command -v gitleaks' "$f" && err "$f resolves gitleaks itself instead of through ci/gitleaks-bin.sh"
done
# One base-ref resolution, likewise (a new CI platform is taught once).
for f in templates/ci-gate/ci/migration-guard.sh templates/ci-gate/ci/unicode-guard.sh templates/ci-gate/ci/diff-coverage.sh; do
  grep -q 'base-ref.sh' "$f" || err "$f must resolve the base ref through ci/base-ref.sh"
  grep -q 'CI_MERGE_REQUEST_DIFF_BASE_SHA' "$f" && err "$f still resolves the base ref itself (ci/base-ref.sh is the one place)"
done
# Every git-range scan carries --text (a `-diff` attribute would hide a file)
# and --diff-merges (a secret added in a merge commit is otherwise invisible),
# and never lets an empty word into --log-opts (that silently scans nothing).
for f in templates/ci-gate/gitlab/ci-gate.gitlab-ci.yml templates/ci-gate/gitlab/ci-gate.shell.gitlab-ci.yml templates/ci-gate/github/gate.yml templates/ci-gate/ci/pre-push.sh templates/ci-gate/ci/gate.sh; do
  grep -q -- '--text --diff-merges=first-parent' "$f" || err "$f: a git-range scan without '--text --diff-merges=first-parent' is blind to -diff attributes and merge commits"
done
for f in templates/ci-gate/gitlab/ci-gate.gitlab-ci.yml templates/ci-gate/gitlab/ci-gate.shell.gitlab-ci.yml templates/ci-gate/github/gate.yml; do
  grep -qF -- '--log-opts="--text --diff-merges=first-parent${RANGE:+ $RANGE}"' "$f" || err "$f: --log-opts must use \${RANGE:+ \$RANGE} (a stray empty word scans nothing)"
  grep -q 'git log --text --diff-merges=first-parent --max-count=1' "$f" || err "$f: validate the range with the same 'git log' gitleaks runs — it exits 0 when the git command inside it fails, and rev-list cannot tell whether git log accepts the options"
done
# unicode-guard's diff must be immune to the knobs reachable from the change
# under review or the developer's own config.
for flag in -- '--text' '--no-ext-diff' '--no-textconv' 'diff.noprefix=false'; do
  [ "$flag" = "--" ] && continue
  grep -q -- "$flag" templates/ci-gate/ci/unicode-guard.sh || err "unicode-guard.sh: git diff must pass $flag"
done
grep -q 'default_install_hook_types' templates/ci-gate/.pre-commit-config.yaml || err ".pre-commit-config.yaml: without default_install_hook_types a plain 'pre-commit install' leaves the pre-push layer uninstalled"
# No literal credential-shaped strings in tracked files: our own secret-scan
# (and every consumer's) would flag the gate's own source.
# (AKIAIOSFODNN7EXAMPLE is AWS's own published example — excluded by the default
# gitleaks ruleset and named in our docs on purpose.)
if git grep -nE '\b(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}\b' -- . ':!CHANGELOG.md' | grep -v 'AKIAIOSFODNN7EXAMPLE' >/dev/null; then
  err "a credential-shaped literal in a tracked file (build it at run time instead):"
  git grep -nE '\b(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}\b' -- . ':!CHANGELOG.md' | grep -v 'AKIAIOSFODNN7EXAMPLE' >&2
fi
# The payload version marker in ci/README.md tracks the plugin version, so a
# consumer can tell which payload they vendored.
PAYLOAD_V=$(sed -nE 's/.*ci-gate payload version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' templates/ci-gate/ci/README.md | head -1)
[ -n "$PAYLOAD_V" ] || err "templates/ci-gate/ci/README.md has no 'ci-gate payload version: X.Y.Z' marker"
[ -z "$PAYLOAD_V" ] || grep -q "^## \[$PAYLOAD_V\]" CHANGELOG.md || err "payload version marker $PAYLOAD_V is not a released version in CHANGELOG.md"
# (release-check.sh is what requires the marker to move when the payload does.)
# The marker form documented everywhere must be the one the guard accepts.
MARKER_DOCS="README.md README.ru.md templates/ci-gate/ci/README.md skills/ci-gate/SKILL.md skills/task/SKILL.md"
# shellcheck disable=SC2086
if grep -nE 'destructive: approved([^ (]|$)' $MARKER_DOCS | grep -vE 'bare|no reason|carries|is not an|approved \(  ?\)' >/dev/null; then
  err "shipped documentation shows a destructive marker without a reason:"
  grep -nE 'destructive: approved([^ (]|$)' $MARKER_DOCS | grep -vE 'bare|no reason|carries|is not an|approved \(  ?\)' >&2
fi
for pth in '/ci/' '/.gitleaks.toml' '/.pre-commit-config.yaml' '/CODEOWNERS'; do
  grep -qF "$pth" templates/ci-gate/CODEOWNERS || err "templates/ci-gate/CODEOWNERS does not own $pth"
done

# 10. unicode-guard matches bytes with awk only: GNU grep in the C locale silently
#     fails to match bracket ranges of bytes >= 0x80 (rc 1 = a clean verdict it
#     never established).
if grep -nE 'grep.*(BIDI_RE|ZW_RE|TAG_RE|BOM_RE)' templates/ci-gate/ci/unicode-guard.sh >/dev/null; then
  err "unicode-guard.sh uses grep on a byte pattern (fail-open on GNU grep in the C locale) — match with awk"
fi
grep -q 'LC_ALL=C awk' templates/ci-gate/ci/unicode-guard.sh || err "unicode-guard.sh must run awk under LC_ALL=C"
grep -q "tr -d '\\\\000'" templates/ci-gate/ci/unicode-guard.sh || err "unicode-guard.sh must strip NUL bytes before awk (busybox awk splits the record there and the tail is never scanned)"
# Case folding is locale-dependent (tr_TR: i/I are not a pair), so a verdict
# must not depend on the runner's locale.
for f in templates/ci-gate/ci/migration-guard.sh templates/ci-gate/ci/unicode-guard.sh templates/ci-gate/ci/diff-coverage.sh templates/ci-gate/ci/gate.sh templates/ci-gate/ci/pre-push.sh; do
  grep -q '^export LC_ALL=C' "$f" || err "$f must pin LC_ALL=C — grep -i and awk case folding are locale-dependent"
done

# 11. task's contracts are cross-file: the vocabulary a runner or a human parses
#     (terminal status, landing verdicts, DoD grading, the reviewed sha) must
#     exist in every place that produces or consumes it.
for w in DONE_WITH_CONCERNS MERGED_NOT_LIVE ABANDONED BLOCKED; do
  grep -q "$w" skills/task/SKILL.md || err "task/SKILL.md lost the terminal status '$w'"
  grep -q "$w" skills/task/references/implementation-integrity.md || err "implementation-integrity.md lost the terminal status '$w'"
done
# The landing field and the terminal status are disjoint vocabularies, and the
# landing table is what defines them — check the table rows, then check that the
# two sets share no token (the hole the split was made to close).
LAND=skills/task/references/land.md
for w in deployed deployed-with-concerns not-live reverted; do
  grep -qE "^\| \`$w\`" "$LAND" || err "$LAND: the landing table has no row for \`$w\`"
done
grep -q 'landing: deployed | deployed-with-concerns | not-live | reverted' "$LAND" || err "$LAND lost the 'landing:' field definition"
for w in DONE DONE_WITH_CONCERNS MERGED_NOT_LIVE BLOCKED ABANDONED; do
  grep -qE "^\| \`$w\`" "$LAND" && err "$LAND: '$w' is a terminal status and must not appear as a landing value"
done
# The status table is a procedure: a row count plus its header, so emptying it
# cannot pass as "the vocabulary is still there".
II=skills/task/references/implementation-integrity.md
grep -q '| Condition | Status |' "$II" || err "$II lost the condition→status table header"
ROWS=$(awk '/^  \| Condition \| Status \|/{t=1;next} t && /^  \|---/{next} t && /^  \|/{n++} t && !/^  \|/{t=0} END{print n+0}' "$II")
[ "$((ROWS))" -ge 7 ] || err "$II: the condition→status table has $ROWS rows, fewer than the outcomes the release named"
flat "$II" | grep -q 'derived, not chosen' || err "$II lost 'the status is derived, not chosen'"
flat "$II" | grep -q 'risk owner is a person outside this flow' || err "$II lost the definition of the risk owner"
# Procedures behind the phase-0 contracts, pinned by their load-bearing phrase.
SK=skills/task/SKILL.md
flat "$SK" | grep -q 'replays what it changes' || err "$SK: the tier ratchet no longer says that it replays anything"
flat "$SK" | grep -q 'premortem #1 are redone' || err "$SK: the tier ratchet no longer names what a phase-3 escalation replays"
flat "$SK" | grep -q 'pulls in T3 artifacts' || err "$SK: one-way reversibility no longer pulls in the T3 artifacts"
flat "$SK" | grep -q 'A PASS with nothing to point at is not a PASS' || err "$SK lost the DoD grading rule"
flat "$SK" | grep -q 'Stage by path' || err "$SK lost the stage-by-path rule"
flat "$SK" | grep -q '<TASK-ID>.spec.md' || err "$SK lost the canonical spec path"
flat "$SK" | grep -q 'state.md' || err "$SK lost the resume rule for a hand-over"
flat skills/task/references/blast-radius.md | grep -q 'An empty result is a claim' || err "blast-radius.md lost 'an empty result is a claim'"
DST=skills/task/references/design-spec-template.md
grep -q '^## 5. Reversibility' "$DST" || err "$DST lost the Reversibility section"
for w in 'Stop condition' 'Compatibility window' 'Rollback'; do
  grep -q "$w" "$DST" || err "$DST: Reversibility lost '$w'"
done
flat "$DST" | grep -q 'What does \*\*not\*\* count' || err "$DST lost the rejection criteria that stop a rollback plan from being fiction"
flat skills/task/references/checkpoint.md | grep -q 'validate before you trust' || err "checkpoint.md lost the resume validation"
grep -q 'Reviewed:' skills/task/references/code-review-prompt.md || err "code-review-prompt.md: the verdict must carry 'Reviewed: <sha>'"
grep -q 'review @' skills/task/references/land.md || err "land.md's evidence block lost the 'review @ <sha>' field"
grep -q 'DoD-n' skills/task/SKILL.md || err "task/SKILL.md lost the DoD-n grading rule"
grep -qE 'DoD-n .*PASS' skills/task/references/code-review-prompt.md || err "code-review-prompt.md lost the DoD-n grading"
grep -q 'only moves up' skills/task/SKILL.md || err "task/SKILL.md lost the 'a tier only moves up' rule"
# One canonical name for the spec file, or a later phase looks for the wrong one.
for f in skills/task/SKILL.md skills/task/references/design-spec-template.md skills/task/references/checkpoint.md; do
  grep -q '\.spec\.md' "$f" || err "$f does not use the canonical <TASK-ID>.spec.md path"
done
# The security pass must not inherit the author's worry-list.
tr '\n' ' ' < skills/task/references/security-review-prompt.md | grep -q 'without its \*Premortem edges\* section' || err "security-review-prompt.md lost the rule that 6b does not receive the premortem edges"
for w in PASS FAIL PARTIAL UNVERIFIABLE; do
  grep -q "$w" skills/task/references/implementation-integrity.md || err "implementation-integrity.md lost the DoD grade '$w'"
done
# The close comment's contract: a status line, a landing line, and an evidence
# example that obeys the rules it points at.
grep -q 'landing:' skills/task/SKILL.md || err "task/SKILL.md does not require the 'landing:' line in the close comment"
grep -q 're-reviewed:' skills/task/references/land.md || err "land.md's close-comment example lost 're-reviewed:' (a bare commit count reads as a judgement)"
grep -q 'pin 20.11.1 · actual' skills/task/references/land.md || err "land.md's example must show the toolchain as pin·actual, not a bare version"
grep -q 'scan-text.sh' skills/task/references/land.md || err "land.md lost scan-at-sink for the close comment"
flat skills/task/SKILL.md | grep -q 'land.md` §5' || err "task/SKILL.md phase 8 no longer points at the close-comment shape in land.md"
grep -q 'gate: absent (' skills/task/SKILL.md || err "task/SKILL.md: 'gate: absent' must carry the command that established it"
# Shipped skills are written in English; Russian belongs only to the output
# templates (the reviewer answers in Russian) and to quoted examples. This
# catches an instruction sentence that slipped in — Cyrillic on a line with no
# quotes, no backticks and no code fence around it.
for f in skills/*/references/*.md; do
  awk -v file="$f" '
    /^```/ { fence = !fence; next }
    fence { next }
    /respond in Russian|Output format|на русском/ { ru = 1 }
    ru { next }
    /[а-яА-Я]/ && $0 !~ /[`"«»]/ { print file ":" NR; found = 1 }
    END { exit found ? 1 : 0 }' "$f" >&2 || err "$f: Russian instruction prose in a shipped English reference (line above)"
done
# Reverse of check 1: a reference nobody loads is a reference nobody reads.
for sk in skills/*/; do
  sk="${sk%/}"; [ -d "$sk/references" ] || continue
  for f in "$sk"/references/*.md; do
    b=$(basename "$f")
    [ -s "$f" ] || err "$f is empty"
    # A load, not a mention: either an explicit per-phase
    # `Read "$ROOT/<skill>/references/<file>"`, or (the decompose style) the
    # generic Read form declared once plus a "load it now" instruction next to
    # the file name. Checked on the flattened text, so a rewrap cannot hide it.
    FLAT=$(flat "$sk/SKILL.md")
    printf '%s' "$FLAT" | grep -qE "Read \"\\\$ROOT/$sk/references/$b\"" \
      || { printf '%s' "$FLAT" | grep -qE 'Read "\$ROOT/'"$sk"'/references/' \
           && printf '%s' "$FLAT" | grep -qE "(Load [^.]{0,40})?references/$b[^.]{0,40}(load it now|load now)|Load .{0,4}references/$b"; } \
      || err "$sk/SKILL.md never instructs a load of $b — a reference nobody loads degrades into memory"
  done
done
grep -q 'one-way' skills/task/SKILL.md || err "task/SKILL.md lost the reversibility classification"
if grep -rn 'git add -A' skills/ | grep -v 'never' >/dev/null; then
  err "a skill tells the agent to 'git add -A' (stage by path):"
  grep -rn 'git add -A' skills/ | grep -v 'never' >&2
fi

# 12. README.md and README.ru.md move in lockstep (structure only; text is a translation).
bash scripts/readme-parity.sh >/dev/null || err "README.md / README.ru.md structure differs (run scripts/readme-parity.sh)"

if [ "$fail" = 0 ]; then echo "lint: OK"; fi
exit "$fail"
