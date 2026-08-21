#!/usr/bin/env bash
# gitleaks-fetch.sh — fetch a PINNED gitleaks binary and verify it against a
# checksum committed to THIS repo (the trust anchor). No docker, no runner
# mutation, no docker-group escalation — works on any shell runner. Prints the
# verified binary path on stdout; all logs go to stderr.
#
# Trust model: the committed SHA256 is checked on EVERY call, not only on the
# first download. The cache (shared between jobs and projects on a shell runner)
# holds only the tarball; each call re-verifies it against the committed sum and
# extracts into a fresh private directory. A cached artifact that no longer
# matches is discarded and re-fetched — never executed.
#
# Maintenance: a pinned scanner goes stale. Bump PIN_VERSION and BOTH SHA256s
# together — plus the image digest in the CI files and the `rev` in
# .pre-commit-config.yaml (see ci/README.md). Get the sums from the release
# checksums at authoring time (verify once, by a human, over a trusted channel —
# do NOT trust a checksums.txt downloaded next to the binary in the same job):
#   curl -sL https://github.com/gitleaks/gitleaks/releases/download/v<V>/gitleaks_<V>_checksums.txt
set -euo pipefail

PIN_VERSION="8.30.1"
SHA256_x64="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
SHA256_arm64="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"

# stdout must carry ONLY the binary path; everything else → stderr.
log() { printf 'gitleaks-fetch: %s\n' "$*" >&2; }

case "$(uname -m)" in
  x86_64|amd64)  ARCH="x64";   WANT="$SHA256_x64" ;;
  aarch64|arm64) ARCH="arm64"; WANT="$SHA256_arm64" ;;
  *) log "unsupported arch $(uname -m)"; exit 2 ;;
esac

sha256_of() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else log "no sha256sum/shasum available"; exit 2; fi
}

CACHE="${GITLEAKS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gitleaks-pinned}"
TARBALL="gitleaks_${PIN_VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${PIN_VERSION}/${TARBALL}"
CACHED="$CACHE/$TARBALL"
mkdir -p "$CACHE"

# 1. A cached tarball is reused only if it STILL matches the committed sum.
if [ -f "$CACHED" ]; then
  if [ "$(sha256_of "$CACHED")" = "$WANT" ]; then
    log "cached tarball verified (v${PIN_VERSION}, ${ARCH})"
  else
    log "cached tarball no longer matches the committed SHA256 — discarding it"
    rm -f "$CACHED"
  fi
fi

# 2. Download into a private temp file, verify, then move into the cache.
if [ ! -f "$CACHED" ]; then
  DL=$(mktemp -d)
  trap 'rm -rf "$DL"' EXIT
  log "downloading pinned v${PIN_VERSION} (${ARCH})"
  if   command -v curl >/dev/null 2>&1; then curl -sSfL "$URL" -o "$DL/$TARBALL"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$DL/$TARBALL" "$URL"
  else log "no curl/wget available"; exit 2; fi
  GOT=$(sha256_of "$DL/$TARBALL")
  if [ "$GOT" != "$WANT" ]; then
    log "CHECKSUM MISMATCH for $TARBALL — refusing to run (fail closed)"
    log "  expected (committed): $WANT"
    log "  got      (download):  $GOT"
    exit 1
  fi
  mv "$DL/$TARBALL" "$CACHED"
  log "verified + cached $CACHED"
fi

# 3. Extract the verified tarball into a fresh private dir for THIS call. The
#    extracted binary is never reused across calls, so a shared cache can only
#    ever serve the tarball that was just re-verified.
RUN=$(mktemp -d "${TMPDIR:-/tmp}/gitleaks-run.XXXXXX")
chmod 0700 "$RUN"
tar -xzf "$CACHED" -C "$RUN"
SRC="$RUN/gitleaks"
[ -x "$SRC" ] || SRC=$(find "$RUN" -type f -name gitleaks | head -1)
[ -n "${SRC:-}" ] && [ -f "$SRC" ] || { log "gitleaks binary not found in tarball"; exit 2; }
chmod 0755 "$SRC"
log "ready: $SRC"
printf '%s\n' "$SRC"
