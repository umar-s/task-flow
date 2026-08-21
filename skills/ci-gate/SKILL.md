---
name: ci-gate
description: >-
  Scaffold a portable, deterministic merge gate into the current repository —
  gitleaks secret-scan, tool-agnostic migration-guard (forward-only + destructive
  DDL marker), pre-commit hooks, and a GitLab/GitHub CI job — then print the
  one-time protected-branch / required-status-check commands. Use when the user
  asks to "add the ci-gate", "set up the deterministic gate", "install
  secret-scan + migration guard", or wires the gate that the `task` skill's
  phase 8 depends on. Not a linter and not an LLM review — it is the non-gameable
  floor under secrets, destructive migrations, and force-push.
---

# ci-gate — scaffold the deterministic merge gate

The template payload lives at **`${CLAUDE_PLUGIN_ROOT}/templates/ci-gate/`**.
Always read files from there — never assume a `~/.claude/...` path (the plugin is
installed in its own directory on each host).

This gate is the deterministic, non-gameable half of the quality flow. It covers
the blast-radius categories that unit tests and an LLM `/security-review` miss:
secrets in the diff, mutated/deleted migrations, unmarked destructive DDL, and
force-push into a protected branch. It does **not** replace review — it sits
under it.

## Steps

1. **Confirm target + platform + executor.** Run from the repo root (`git
   rev-parse --show-toplevel`). Detect the CI platform: `.gitlab-ci.yml` →
   GitLab, `.github/` → GitHub. For **GitLab**, also determine the runner
   **executor** — this decides which CI file to drop:
   - `docker` / `kubernetes` executor → `gitlab/ci-gate.gitlab-ci.yml` (uses `image:`).
   - `shell` executor → `gitlab/ci-gate.shell.gitlab-ci.yml`. On a shell runner
     `image:` is **ignored**, so the docker variant silently won't run. The shell
     variant fetches a pinned, checksum-verified gitleaks in-job (no docker, no
     runner change, no docker-group escalation) and runs migration-guard directly.
   Check `.gitlab-ci.yml`/runner config if visible; if unknown, **ask** (executor
   type + the shell runner's tag). GitHub hosted runners have docker — use
   `github/gate.yml` as-is.

2. **Copy the payload** from `${CLAUDE_PLUGIN_ROOT}/templates/ci-gate/`:
   - `ci/` (migration-guard.sh, diff-coverage.sh, gate.sh, gitleaks-fetch.sh,
     README.md) → `<repo>/ci/`
   - `.gitleaks.toml`, `.pre-commit-config.yaml` → repo root
   - **GitLab (docker/k8s):** `gitlab/ci-gate.gitlab-ci.yml` →
     `<repo>/ci/ci-gate.gitlab-ci.yml`, then add
     `include: [ { local: 'ci/ci-gate.gitlab-ci.yml' } ]` to the project
     `.gitlab-ci.yml` (create if absent).
   - **GitLab (shell):** `gitlab/ci-gate.shell.gitlab-ci.yml` →
     `<repo>/ci/ci-gate.shell.gitlab-ci.yml`, add the matching `include:`, and set
     a project CI/CD variable `GATE_RUNNER_TAG` = the shell runner's tag (the CI
     file references `tags: ["$GATE_RUNNER_TAG"]`). Host needs git/bash/grep/curl/
     tar/sha256sum.
   - **GitHub:** `github/gate.yml` → `<repo>/.github/workflows/gate.yml`.
   - `chmod +x ci/*.sh`.
   Do not overwrite an existing project `.gitlab-ci.yml` — merge the `include:`.

3. **Local layer:** tell the user to run `pip install pre-commit && pre-commit
   install` so secrets are caught before push. Do not run global installs yourself.
   `bash ci/gate.sh --staged` runs the whole gate locally; `GATE_PINNED_ONLY=1`
   makes it use the pinned scanner instead of whatever `gitleaks` is on `PATH`.

4. **Configure the two project-specific knobs.**
   - **Migration dirs** — if the repo's migrations are not under a default
     (`migrations db/migrate db/migration prisma/migrations`), set
     `MIGRATION_DIRS` in the CI job env and the pre-commit hook `entry`.
   - **Changed-line coverage** — `ci/diff-coverage.sh` *judges* a coverage
     report, it never produces one. Uncomment the `diff-coverage` job in the CI
     file, point `GATE_COVERAGE_REPORT` at whatever the project's test job
     already writes (lcov / Cobertura / Clover — jest, vitest, pytest-cov,
     PHPUnit, JaCoCo, `go tool cover` all emit one of the three), and declare
     that job's artifact as its dependency. Start at `GATE_COVERAGE_MIN=80`:
     global coverage % is vanity — it moves too slowly to notice an untested
     change — changed lines are the constraint. Left unset, the layer skips
     itself and says so; an honest skip is fine, a threshold nobody configured
     is not a gate.

5. **Protected-branch (one-time, per repo).** This CANNOT be a CI job — by the
   time a pipeline runs, the push already happened. It is a platform rule. Print
   the commands (fill in owner/repo/branch) and offer to run them; confirm before
   executing, since they change repo settings (outward-facing).

   **GitLab (glab):**
   ```bash
   PROJ="group/repo"; BR="main"; ID=$(printf %s "$PROJ" | jq -sRr @uri)
   glab api -X PUT "projects/$ID" \
     -f only_allow_merge_if_pipeline_succeeds=true \
     -f only_allow_merge_if_all_discussions_are_resolved=true
   glab api -X DELETE "projects/$ID/protected_branches/$BR" 2>/dev/null || true
   glab api -X POST  "projects/$ID/protected_branches?name=$BR&allow_force_push=false"
   ```

   **GitHub (gh)** — `contexts` must match the workflow job names:
   ```bash
   gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
   {
     "required_status_checks": { "strict": true, "contexts": ["secret-scan", "migration-guard"] },
     "enforce_admins": true,
     "required_pull_request_reviews": null,
     "restrictions": null
   }
   JSON
   ```

6. **Negative control — prove the gate can fail before trusting its pass.**
   Don't just run it green: run it against a *known-bad* throwaway staged
   change and watch it go red. Stage a new migration holding `DROP TABLE x;`
   with no marker (expect `migration-guard` exit 1) plus a line shaped like a
   real credential (expect gitleaks to trip), then `bash ci/gate.sh --staged`.
   Restore the throwaway change afterwards. A gate nobody has seen fail is not
   known to work: a mis-set `MIGRATION_DIRS`, a scanner that never started, and
   a genuinely clean diff all print the same thing. Exit codes: `0` ok · `1`
   policy violation · `2` config/infra (fails closed).
   Once coverage is wired, control it the same way: push a changed line the
   report shows as `hits=0` and watch `diff-coverage` exit 1. Only after you
   have seen that, set `GATE_COVERAGE_STRICT=1` — a report path that points at
   nothing measurable otherwise reads exactly like a fully covered diff.
   Be precise about what this buys — it proves one known-bad input reaches the
   failure path. It does not prove the checker recognises every violation of
   the rule it stands for.

## Scan strategy (already wired in the CI files)
- **Secret-scan is incremental:** MR/PR → the MR's commit range; default-branch
  push → only the newly-pushed commits (`before..after`, with a full-scan
  fallback on the zero-SHA first push); **scheduled** pipeline → full-history
  audit. Don't switch default-branch pushes back to full history — it is O(history)
  per push and re-flags every legacy secret forever.
- Keep the scheduled full audit (GitLab: a pipeline schedule; GitHub: the `cron`
  already in `gate.yml`) so a secret slipped into history out-of-band still gets
  caught eventually.

## Guardrails
- The gate is a floor, not a lint pass — never weaken a rule to make a diff pass;
  fix the diff or add the explicit `-- destructive: approved` marker with a reason.
- **Gate code fails closed or it is theatre.** The dangerous failure of a checker
  is not a crash — it is nothing crashing while the layer prints "pass". Keep
  `set -euo pipefail`; never `|| true` and never `2>/dev/null` on a command whose
  result decides the verdict; spell out ambiguous exit codes. For a
  must-find-nothing grep, rc 1 (no match) is the only pass — rc 0 means the
  forbidden pattern is present and rc ≥ 2 means the check itself broke, and both
  must fail the job. The same rule covers reading a file the gate is about to
  judge: an unreadable input is a failure, never an empty one that sails through
  the pattern scan.
- **Coverage is a detector, not a target.** The threshold exists to surface
  changed code no test executes; it never justifies a test written to touch
  lines without asserting anything. That kind of test converts a known gap into
  a false green, and this gate cannot tell the difference — the phase-5 mutation
  check in the `task` skill is what can. Raise the threshold as the suite earns
  it; never lower it to make one MR pass.
- Keep the gitleaks allowlist tight — every entry is a hole. Prefer an inline
  `# gitleaks:allow` on a one-off doc line over a global regex.
- **Pinned gitleaks is a maintenance commitment.** One version, pinned in every
  path: `ci/gitleaks-fetch.sh` (version + committed SHA256, re-verified on every
  call), the docker/GitHub CI files (image **digest**, never `:latest` — a tag
  is re-pointable) and `.pre-commit-config.yaml` (`rev` = commit SHA of the
  release tag). A frozen scanner goes stale (misses new secret formats): bump
  `PIN_VERSION`, both SHA256s, the image digest and the `rev` together; never
  `pre-commit autoupdate` the file.
- **migration-guard reads SQL and the common ORM DSL tokens, per line, in the
  forward part of a migration** (a conventional `down()` is not judged). A
  statement split across lines, SQL built inside a string or a DSL it does not
  list is its documented residue (`ci/README.md` → Known limits) and belongs
  to the phase-6b security review — do not grow the regex into a parser.
- Never fetch and trust a `checksums.txt` alongside the binary in the same job —
  the committed SHA256 in `gitleaks-fetch.sh` is the trust anchor.
- On a shell runner, do **not** solve the docker dependency by adding the runner
  to the `docker` group — socket access there is host root. The pinned fetch
  exists precisely to avoid that.
- `dep/SCA` is language-specific and shipped as a commented stub — wire it to the
  repo's runtime (`npm audit` / `pip-audit` / `govulncheck` / …).
