#!/usr/bin/env bash
# gitleaks-fetch.sh — fetch a PINNED gitleaks binary and verify it against a
# checksum committed to THIS repo (the trust anchor). No docker, no runner
# mutation, no docker-group escalation — works on any shell runner. Prints the
# verified binary path on stdout; all logs go to stderr.
#
# Maintenance: a pinned scanner goes stale. Bump PIN_VERSION and BOTH SHA256s
# together. Get the values from the release checksums at authoring time (verify
# once, by a human, over a trusted channel — do NOT trust a checksums.txt
# downloaded next to the binary in the same job):
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
BIN="$CACHE/gitleaks-${PIN_VERSION}-${ARCH}"

# Reuse a previously fetched+verified binary.
if [ -x "$BIN" ]; then printf '%s\n' "$BIN"; exit 0; fi

mkdir -p "$CACHE"
TARBALL="gitleaks_${PIN_VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${PIN_VERSION}/${TARBALL}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log "downloading pinned v${PIN_VERSION} (${ARCH})"
if   command -v curl >/dev/null 2>&1; then curl -sSfL "$URL" -o "$TMP/$TARBALL"
elif command -v wget >/dev/null 2>&1; then wget -qO "$TMP/$TARBALL" "$URL"
else log "no curl/wget available"; exit 2; fi

GOT=$(sha256_of "$TMP/$TARBALL")
if [ "$GOT" != "$WANT" ]; then
  log "CHECKSUM MISMATCH for $TARBALL — refusing to run (fail closed)"
  log "  expected (committed): $WANT"
  log "  got      (download):  $GOT"
  exit 1
fi

tar -xzf "$TMP/$TARBALL" -C "$TMP"
SRC="$TMP/gitleaks"
[ -x "$SRC" ] || SRC=$(find "$TMP" -type f -name gitleaks | head -1)
[ -n "${SRC:-}" ] && [ -f "$SRC" ] || { log "gitleaks binary not found in tarball"; exit 2; }
cp "$SRC" "$BIN"; chmod 0755 "$BIN"
log "verified + installed at $BIN"
printf '%s\n' "$BIN"
