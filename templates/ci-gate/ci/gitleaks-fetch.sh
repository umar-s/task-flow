#!/usr/bin/env bash
# gitleaks-fetch.sh — fetch a PINNED gitleaks binary and verify it against a
# checksum committed to THIS repo (the trust anchor). No docker, no runner
# mutation, no docker-group escalation — works on any shell runner. Prints the
# verified binary path on stdout; all logs go to stderr.
#
# Trust model: the committed SHA256 is checked on EVERY call, not only on the
# first download, and always on a PRIVATE copy — the shared cache (one per user
# on a shell runner, reachable by every job of that user) only ever holds the
# tarball; each call copies it into a fresh private directory, verifies that
# copy, and extracts that copy. Nothing read from the shared cache is executed
# without passing the committed sum first. A cached tarball that no longer
# matches is discarded and re-fetched.
#
# Cleanup: the extracted binary lives in a per-call directory under
# GITLEAKS_RUN_DIR (default: $TMPDIR or /tmp) and is NOT removed by this script
# — the caller needs it after this process exits. Callers remove it (gate.sh
# traps it; the CI templates point GITLEAKS_RUN_DIR at the job workspace).
#
# Maintenance: a pinned scanner goes stale. Bump PIN_VERSION and ALL FOUR SHA256s
# together — plus the image digest in the CI files and the `rev` in
# .pre-commit-config.yaml (see ci/README.md). Get the sums from the release
# checksums at authoring time (verify once, by a human, over a trusted channel —
# do NOT trust a checksums.txt downloaded next to the binary in the same job):
#   curl -sL https://github.com/gitleaks/gitleaks/releases/download/v<V>/gitleaks_<V>_checksums.txt
set -euo pipefail

PIN_VERSION="8.30.1"
SHA256_linux_x64="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
SHA256_linux_arm64="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
SHA256_darwin_x64="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
SHA256_darwin_arm64="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"

# stdout must carry ONLY the binary path; everything else → stderr.
log() { printf 'gitleaks-fetch: %s\n' "$*" >&2; }

# Platform: the tarball name carries OS and arch, and each combination has its
# own committed sum. An unsupported platform fails closed with a way out — it
# must never download a Linux binary onto a mac and block every push.
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *) log "no pinned build for $(uname -s) — install gitleaks v${PIN_VERSION} on PATH (and unset GATE_PINNED_ONLY)"; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) log "unsupported arch $(uname -m) — install gitleaks v${PIN_VERSION} on PATH"; exit 2 ;;
esac
eval "WANT=\${SHA256_${OS}_${ARCH}:-}"
[ -n "${WANT:-}" ] || { log "no committed SHA256 for ${OS}_${ARCH}"; exit 2; }

# Pick the checksum tool up front: an `exit` inside $(…) would only end the
# subshell and surface as a misleading "checksum mismatch".
if   command -v sha256sum >/dev/null 2>&1; then sha256_of() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum    >/dev/null 2>&1; then sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
else log "no sha256sum/shasum available"; exit 2; fi

CACHE="${GITLEAKS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gitleaks-pinned}"
TARBALL="gitleaks_${PIN_VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${PIN_VERSION}/${TARBALL}"
CACHED="$CACHE/$TARBALL"
RUN_BASE="${GITLEAKS_RUN_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$CACHE" "$RUN_BASE"

# Private per-call directory: everything verified or executed lives here.
RUN=$(mktemp -d "$RUN_BASE/gitleaks-run.XXXXXX")
chmod 0700 "$RUN"
# On any failure nothing half-verified is left behind; on success RUN stays.
trap 'rm -rf "$RUN"' ERR

# 1. Take a private copy of the cached tarball and verify THAT copy. The shared
#    file is never read twice — a neighbour swapping it between check and use
#    can only make this call re-download, never run an unverified binary. The
#    cache is an optimisation: a copy that fails (removed, unreadable, truncated
#    under us) means "not cached", never "job failed".
if [ -f "$CACHED" ]; then
  if cp "$CACHED" "$RUN/$TARBALL" 2>/dev/null && [ "$(sha256_of "$RUN/$TARBALL")" = "$WANT" ]; then   # lint: allow
    log "cached tarball verified (v${PIN_VERSION}, ${OS}_${ARCH})"
  else
    log "cached tarball unreadable or no longer matches the committed SHA256 — discarding it"
    rm -f "$CACHED" "$RUN/$TARBALL" 2>/dev/null || true   # lint: allow — best effort on a shared file
  fi
fi

# 2. Download into the private dir, verify, then publish to the cache with a
#    same-filesystem rename (staging dir inside the cache) so a concurrent
#    reader never sees a half-written tarball.
if [ ! -f "$RUN/$TARBALL" ]; then
  log "downloading pinned v${PIN_VERSION} (${OS}_${ARCH})"
  if   command -v curl >/dev/null 2>&1; then curl -sSfL "$URL" -o "$RUN/$TARBALL"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$RUN/$TARBALL" "$URL"
  else log "no curl/wget available"; rm -rf "$RUN"; exit 2; fi
  GOT=$(sha256_of "$RUN/$TARBALL")
  if [ "$GOT" != "$WANT" ]; then
    log "CHECKSUM MISMATCH for $TARBALL — refusing to run (fail closed)"
    log "  expected (committed): $WANT"
    log "  got      (download):  $GOT"
    rm -rf "$RUN"
    exit 1
  fi
  # Caching is best effort: a read-only or full cache dir must not fail a job
  # whose binary is already verified.
  if STAGE=$(mktemp -d "$CACHE/.dl.XXXXXX" 2>/dev/null) && cp "$RUN/$TARBALL" "$STAGE/$TARBALL" 2>/dev/null && mv -f "$STAGE/$TARBALL" "$CACHED" 2>/dev/null; then   # lint: allow
    rmdir "$STAGE" 2>/dev/null || true   # lint: allow
    log "verified + cached $CACHED"
  else
    rm -rf "${STAGE:-}" 2>/dev/null || true   # lint: allow
    log "verified; cache dir $CACHE not writable — not cached"
  fi
fi

# 3. Extract the verified private copy.
tar -xzf "$RUN/$TARBALL" -C "$RUN"
SRC="$RUN/gitleaks"
[ -x "$SRC" ] || SRC=$(find "$RUN" -type f -name gitleaks | head -1)
[ -n "${SRC:-}" ] && [ -f "$SRC" ] || { log "gitleaks binary not found in tarball"; rm -rf "$RUN"; exit 2; }
chmod 0755 "$SRC"
rm -f "$RUN/$TARBALL"
log "ready: $SRC"
printf '%s\n' "$SRC"
