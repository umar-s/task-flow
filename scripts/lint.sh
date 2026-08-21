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
[ "$DIGESTS" = 1 ] || err "gitleaks image digest differs between CI files ($DIGESTS distinct values)"
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

# 9. README.md and README.ru.md move in lockstep (structure only; text is a translation).
bash scripts/readme-parity.sh >/dev/null || err "README.md / README.ru.md structure differs (run scripts/readme-parity.sh)"

if [ "$fail" = 0 ]; then echo "lint: OK"; fi
exit "$fail"
