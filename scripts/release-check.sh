#!/usr/bin/env bash
# release-check.sh — pre-flight for the four-step release ritual (CLAUDE.md →
# Conventions): bump in plugin.json, CHANGELOG section + compare link, annotated
# tag, GitHub Release. Reads only; never writes.
#
# States it distinguishes (nothing in between is legal):
#   UNRELEASED  plugin.json version has no tag yet → CHANGELOG must carry it and
#               skills/templates must differ from the previous tag.
#   RELEASED    tag exists and HEAD's skills/templates equal the tag's → clean.
#   DRIFT       tag exists but skills/templates changed after it → a behaviour
#               change shipped without a bump (installs track main, not tags).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
err() { printf 'release-check: %s\n' "$*" >&2; fail=1; }

V=$(jq -r .version .claude-plugin/plugin.json)
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "plugin.json version '$V' is not X.Y.Z"

# CHANGELOG: top section == version, compare link present, headings strictly decreasing.
TOP=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | tr -d '#[] ')
[ "$V" = "$TOP" ] || err "plugin.json is $V but the top CHANGELOG section is ${TOP:-missing}"
grep -q "^\[$V\]: " CHANGELOG.md || err "CHANGELOG.md lacks the compare link '[$V]: …'"
prev=""
while read -r h; do
  if [ -n "$prev" ] && [ "$(printf '%s\n%s\n' "$h" "$prev" | sort -V | tail -1)" != "$prev" ]; then
    err "CHANGELOG order: $h listed after $prev"
  fi
  prev=$h
done < <(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | tr -d '#[] ')

# Tag state. Comparisons are tag → WORKING TREE (no HEAD), so an uncommitted
# change counts: this runs before the release commit, not only after it.
BEHAVIOUR="skills templates .claude-plugin"
if git rev-parse -q --verify "refs/tags/v$V^{commit}" >/dev/null; then
  TAGV=$(git show "v$V:.claude-plugin/plugin.json" | jq -r .version)
  [ "$TAGV" = "$V" ] || err "tag v$V carries plugin.json version $TAGV"
  # shellcheck disable=SC2086
  if git diff --quiet "v$V" -- $BEHAVIOUR; then
    state=RELEASED
  else
    state=DRIFT
    err "skills/templates changed after tag v$V without a version bump:"
    # shellcheck disable=SC2086
    git diff --stat "v$V" -- $BEHAVIOUR >&2
  fi
else
  state=UNRELEASED
  PREV=$(git tag -l 'v*' --sort=-v:refname | head -1)
  if [ -n "$PREV" ]; then
    # Compare skills/templates ONLY — .claude-plugin differs by definition (the bump itself).
    git diff --quiet "$PREV" -- skills templates && err "version bumped to $V but skills/templates equal $PREV — a release needs a behaviour change"
    [ "$(printf '%s\n%s\n' "${PREV#v}" "$V" | sort -V | tail -1)" = "$V" ] || err "version $V is not above the latest tag $PREV"
  fi
fi

# The vendored payload carries its own version marker so a consumer can tell
# which copy they have: when templates/ci-gate changed since the last tag, the
# marker must be this release (a plugin-only release leaves it alone).
LAST=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [ -n "$LAST" ] && ! git diff --quiet "$LAST" -- templates/ci-gate; then
  PAYLOAD_V=$(sed -nE 's/.*ci-gate payload version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' templates/ci-gate/ci/README.md | head -1)
  [ "$PAYLOAD_V" = "$V" ] || err "templates/ci-gate changed since $LAST but its version marker says ${PAYLOAD_V:-none}, not $V"
fi

bash scripts/lint.sh || fail=1

if [ "$fail" = 0 ]; then
  echo "release-check: OK — $V ($state)"
  [ "$state" = UNRELEASED ] && echo "next: git tag -a v$V -m 'task-flow $V' && gh release create v$V --notes-file <section> --verify-tag"
fi
exit "$fail"
