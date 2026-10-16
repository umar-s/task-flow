#!/usr/bin/env bash
# codex-security-mock.sh — acceptance for the docker variant of
# templates/ci-gate/gitlab/codex-security.gitlab-ci.yml, run by hand (needs
# docker and network for apt/npm; never in CI). It executes the job's OWN
# before_script + script, read from the YAML, inside the pinned image, with
# `--mock` (synthetic findings across every severity, no LLM, no credentials),
# then the gate job's script on the artifact it produced.
#
#   bash scripts/codex-security-mock.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
YML=templates/ci-gate/gitlab/codex-security.gitlab-ci.yml
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); printf 'ok   %s\n' "$*"; }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

python3 - "$YML" "$TMP" <<'PY'   # PyYAML may live in user site-packages; the input is this repo's own file
import sys, yaml
y = yaml.safe_load(open(sys.argv[1])); out = sys.argv[2]
job, gate = y["codex-security"], y["codex-security-gate"]
open(f"{out}/image", "w").write(job["image"])
# The job's own `variables:` first, exported as the runner would; then
# before_script + script in ONE shell, as GitLab concatenates them, with a
# check between them that the CLI installed is the pinned one.
exports = "".join(f"export {k}='{v}'\n" for k, v in job.get("variables", {}).items())
check = 'v="$(node -p "require(\'$CLI_DIR/node_modules/@openai/codex-security/package.json\').version")"; [ "$v" = "$CODEX_SECURITY_VERSION" ] || { echo "installed CLI $v != pinned $CODEX_SECURITY_VERSION" >&2; exit 3; }\n'
open(f"{out}/job.sh", "w").write("set -e\n" + exports + "\n".join(job["before_script"]) + "\n" + check + "\n".join(job["script"]) + "\n")
open(f"{out}/gate.sh", "w").write("\n".join(gate["script"]) + "\n")
assert gate["image"] == job["image"], "gate and scan must use the one pinned image"
PY
IMAGE=$(cat "$TMP/image")
case "$IMAGE" in *@sha256:*) ok "image pinned by digest" ;; *) bad "image not pinned by digest: $IMAGE" ;; esac

# A merge request: one base commit, one change on top.
R="$TMP/repo"; git init -q -b main "$R"
git -C "$R" -c user.email=m@example.invalid -c user.name=m commit -q --allow-empty -m base
BASE=$(git -C "$R" rev-parse HEAD)
printf 'import os\nos.system(input())\n' > "$R/app.py"
git -C "$R" add app.py; git -C "$R" -c user.email=m@example.invalid -c user.name=m commit -qm change
HEAD_SHA=$(git -C "$R" rev-parse HEAD)
# The job scripts travel beside the checkout, never inside it: the scan refuses
# a dirty tree.
ST="$TMP/stage"; mkdir -p "$ST/shim"; cp "$TMP/job.sh" "$TMP/gate.sh" "$ST/"; cp -R "$R" "$ST/p"
# A shim in front of npm records what the install step can see: the key in its
# environment, and whether it can read the job's initial environment (PID 1).
cat > "$ST/shim/npm" <<'EOF'
#!/bin/sh
e=$(env | grep -c '^CODEX_SECURITY_API_KEY=')
if p=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null); then p=$(printf '%s\n' "$p" | grep -c '^CODEX_SECURITY_API_KEY='); else p=unreadable; fi
line="env=$e proc1=$p uid=$(id -u)"
self=$(dirname "$0")
if [ -d /stage-probe ]; then printf '%s\n' "$line" > /stage-probe/npm; else printf '%s\n' "$line" > "$self/npm-probe"; fi
for d in $(printf '%s' "$PATH" | tr ':' ' '); do [ "$d" = "$self" ] && continue; [ -x "$d/npm" ] && exec "$d/npm" "$@"; done
echo "shim: no real npm" >&2; exit 127
EOF
chmod +x "$ST/shim/npm"

job() {  # rc-file, out-dir, [env...]: the job in the pinned image, artifacts back out
  local rcf="$1" outd="$2"; shift 2; mkdir -p "$outd"
  local envs=(-e CI_JOB_ID=4242 -e CI_PROJECT_DIR=/builds/p -e CI_MERGE_REQUEST_DIFF_BASE_SHA="$BASE" -e CI_COMMIT_SHA="$HEAD_SHA")
  local e; for e in "$@"; do envs+=(-e "$e"); done
  tar -C "$ST" -c . | docker run --rm -i "${envs[@]}" "$IMAGE" bash -c '
    mkdir -p /stage /builds /stage-probe && chmod 1777 /stage-probe && tar -x -C /stage && mv /stage/p /builds/p && cd /builds/p &&
    export PATH="/stage/shim:$PATH" &&
    printf "[safe]\n\tdirectory = /builds/p\n" > "$HOME/.gitconfig"   # the runner clones as the job user; tar here keeps the host uid
    rc=0; bash /stage/job.sh >&2 || rc=$?
    printf "%s\n" "$rc" > job-rc.txt
    cp /stage-probe/npm npm-probe.txt 2>/dev/null || echo "npm never ran" > npm-probe.txt
    tar -c job-rc.txt npm-probe.txt $(ls -d codex-security-artifacts 2>/dev/null)' | tar -x -C "$outd"   # lint: allow — harness plumbing, the verdicts are checked below
  cat "$outd/job-rc.txt" > "$rcf"
}

# 1. With findings at every severity and the default threshold, the job itself
#    succeeds, carries a SARIF and records exit 1; the gate restores 1.
job "$TMP/rc1" "$TMP/out1" CODEX_SECURITY_API_KEY=mock-not-a-key CODEX_SECURITY_EXTRA_ARGS=--mock
[ "$(cat "$TMP/rc1")" = 0 ] && ok "scan job exits 0 with the pinned CLI (the gate job decides)" || bad "scan job rc=$(cat "$TMP/rc1") (3 = the installed CLI is not the pinned version)"
A="$TMP/out1/codex-security-artifacts"
grep -qx 'env=0 proc1=unreadable uid=1000' "$TMP/out1/npm-probe.txt" && ok "npm ran as node without the key and could not read PID 1's environment" || bad "npm probe: $(cat "$TMP/out1/npm-probe.txt")"
[ -s "$A/results.sarif" ] && ok "SARIF written" || bad "no SARIF"
[ -s "$A/scan.json" ] && ok "scan JSON kept as an artifact" || bad "no scan.json artifact"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["version"]=="2.1.0" and d["runs"][0]["results"]' "$A/results.sarif" \
  && ok "SARIF 2.1.0 with results" || bad "SARIF is not 2.1.0 with results"
[ "$(cat "$A/scan-exit-code.txt" 2>/dev/null)" = 1 ] && ok "scan exit 1 recorded (findings ≥ high)" || bad "scan-exit-code.txt=$(cat "$A/scan-exit-code.txt" 2>/dev/null)"
rc=0; (cd "$TMP/out1" && sh "$ST/gate.sh") || rc=$?
[ "$rc" = 1 ] && ok "gate restores exit 1" || bad "gate rc=$rc, expected 1"
# 2. The gate fails closed on a missing or garbled artifact.
mkdir -p "$TMP/g2"; rc=0; (cd "$TMP/g2" && sh "$ST/gate.sh" 2>/dev/null) || rc=$?
[ "$rc" = 2 ] && ok "gate: missing artifact → 2" || bad "gate on a missing artifact rc=$rc"
mkdir -p "$TMP/g3/codex-security-artifacts"; echo oops > "$TMP/g3/codex-security-artifacts/scan-exit-code.txt"
rc=0; (cd "$TMP/g3" && sh "$ST/gate.sh" 2>/dev/null) || rc=$?
[ "$rc" = 2 ] && ok "gate: garbled exit code → 2" || bad "gate on a garbled exit code rc=$rc"
# 3. No key → the job fails closed before any scan.
job "$TMP/rc3" "$TMP/out3" CODEX_SECURITY_EXTRA_ARGS=--mock
[ "$(cat "$TMP/rc3")" = 2 ] && ok "no API key → job exits 2" || bad "no API key: job rc=$(cat "$TMP/rc3")"
[ ! -e "$TMP/out3/codex-security-artifacts/scan-exit-code.txt" ] && ok "no API key → no exit-code artifact" || bad "an exit code was recorded without a scan"
grep -qx 'npm never ran' "$TMP/out3/npm-probe.txt" && ok "no API key → nothing installed (fails before the network)" || bad "no API key: npm still ran"

# 4. Shell variant, on this host: the job's before_script + script + after_script
#    with bash, the CLI in a per-job TMPDIR (needs node, npm, git; network for npm).
SH_YML=templates/ci-gate/gitlab/codex-security.shell.gitlab-ci.yml
python3 - "$SH_YML" "$TMP" <<'PY2'
import sys, yaml
y = yaml.safe_load(open(sys.argv[1])); out = sys.argv[2]
job, gate = y["codex-security"], y["codex-security-gate"]
assert "image" not in job and "image" not in gate, "a shell variant must not carry image:"
exports = "".join(f"export {k}='{v}'\n" for k, v in job.get("variables", {}).items())
open(f"{out}/sh-job.sh", "w").write(exports + "\n".join(job["before_script"] + job["script"]) + "\n")
assert "after_script" not in job, "cleanup is the EXIT trap's (after_script cannot know mktemp paths)"
PY2
sh_job() {  # rc-file, workdir, path-prefix, [env...]
  local rcf="$1" wd="$2" pre="$3"; shift 3
  cp -R "$R" "$wd"; mkdir -p "$TMP/t"; chmod 700 "$TMP/t"   # the scanner refuses a group-writable parent without the sticky bit
  local rc=0
  (cd "$wd" && env PATH="$pre:$PATH" TMPDIR="$TMP/t" CI_JOB_ID=4243 CI_PROJECT_DIR="$wd" \
     CI_MERGE_REQUEST_DIFF_BASE_SHA="$BASE" CI_COMMIT_SHA="$HEAD_SHA" CODEX_SECURITY_NO_UPDATE_NOTICE=1 "$@" \
     bash "$TMP/sh-job.sh" > "$TMP/sh.log" 2>&1) || rc=$?
  printf '%s\n' "$rc" > "$rcf"
}
mkdir -p "$TMP/oldpy"; printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Python 3.8.0"; exit 0; }\nexit 1\n' > "$TMP/oldpy/python3"; chmod +x "$TMP/oldpy/python3"
sh_job "$TMP/rc4" "$TMP/w4" "$TMP/oldpy" CODEX_SECURITY_API_KEY=mock-not-a-key CODEX_SECURITY_EXTRA_ARGS=--mock
[ "$(cat "$TMP/rc4")" = 2 ] && grep -q 'older than 3.10' "$TMP/sh.log" && ok "shell: python3 < 3.10 → exits 2 before installing" || { bad "shell: old python rc=$(cat "$TMP/rc4")"; tail -5 "$TMP/sh.log" >&2; }
PY_OK=""; for c in python3.13 python3.12 python3.11 python3.10; do command -v "$c" >/dev/null && { PY_OK=$(command -v "$c"); break; }; done
if [ -z "$PY_OK" ]; then
  bad "shell: no python3.10+ on this host — positive shell case not run"
else
  mkdir -p "$TMP/newpy"; ln -s "$PY_OK" "$TMP/newpy/python3"
  cp "$ST/shim/npm" "$TMP/newpy/npm"
  sh_job "$TMP/rc5" "$TMP/w5" "$TMP/newpy" CODEX_SECURITY_API_KEY=mock-not-a-key CODEX_SECURITY_EXTRA_ARGS=--mock
  grep -q '^env=0 ' "$TMP/newpy/npm-probe" && ok "shell: npm ran without the key in its environment" || bad "shell npm probe: $(cat "$TMP/newpy/npm-probe" 2>&1)"
  [ "$(cat "$TMP/rc5")" = 0 ] && ok "shell: scan job exits 0" || { bad "shell: job rc=$(cat "$TMP/rc5")"; tail -8 "$TMP/sh.log" >&2; }
  [ "$(cat "$TMP/w5/codex-security-artifacts/scan-exit-code.txt" 2>/dev/null)" = 1 ] && ok "shell: scan exit 1 recorded" || bad "shell: no exit 1 recorded"
  [ -s "$TMP/w5/codex-security-artifacts/results.sarif" ] && ok "shell: SARIF written" || bad "shell: no SARIF"
  left=$(ls -A "$TMP/t" | grep '^codex-security' || true)   # lint: allow — node keeps its own compile cache in TMPDIR
  [ -z "$left" ] && ok "shell: the EXIT trap removed the private work directory" || bad "shell: paths left behind: $left"
  sh_job "$TMP/rc6" "$TMP/w6" "$TMP/newpy" CODEX_SECURITY_AUTH=bogus CODEX_SECURITY_EXTRA_ARGS=--mock
  [ "$(cat "$TMP/rc6")" = 2 ] && ok "shell: unknown CODEX_SECURITY_AUTH → 2" || bad "shell: bogus auth rc=$(cat "$TMP/rc6")"
fi

echo "codex-security-mock: $pass passed, $fail failed"
[ "$fail" = 0 ]
