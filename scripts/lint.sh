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

# 5. Axioms as text invariants (CLAUDE.md → "The central axiom", "Clean-context dispatch").
grep -q 'deterministic gate' skills/task/SKILL.md || err "task phase 8 lost the 'deterministic gate' clause"
grep -q 'never the session transcript' skills/task/SKILL.md || err "task phase 6 lost the clean-context clause"
grep -q 'fresh context' skills/decompose/SKILL.md || err "decompose phase 5 lost the fresh-context clause"
grep -q 'factual' skills/task/references/code-review-prompt.md || err "code-review-prompt lost the 'WHAT_CHANGED is factual' rule"

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
PV=$(jq -r .version .claude-plugin/plugin.json)
grep -q "ci-gate payload version: $PV" templates/ci-gate/ci/README.md || err "templates/ci-gate/ci/README.md: payload version marker is not $PV"
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

# 11. README.md and README.ru.md move in lockstep (structure only; text is a translation).
bash scripts/readme-parity.sh >/dev/null || err "README.md / README.ru.md structure differs (run scripts/readme-parity.sh)"

if [ "$fail" = 0 ]; then echo "lint: OK"; fi
exit "$fail"
