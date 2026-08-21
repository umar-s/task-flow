---
name: ci-gate
description: >-
  Scaffold a portable, deterministic merge gate into the current repository —
  gitleaks secret-scan (pre-commit, pre-push, CI), tool-agnostic
  migration-guard (forward-only + destructive DDL marker with a reason),
  unicode-guard (Trojan Source), CODEOWNERS on the gate files, a scan-at-sink
  script for outgoing text, and a GitLab/GitHub CI job — then print the
  one-time protected-branch / required-review commands and prove the gate
  can fail (`gate.sh --selftest`). Use when the user
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
secrets in the diff, mutated/deleted migrations, unmarked destructive DDL,
invisible code points in added lines, and force-push into a protected branch.
It does **not** replace review — it sits under it, and out of reach of the MR
it judges (the gate files are under required code-owner review).

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
   - the whole `ci/` directory → `<repo>/ci/` (copy it wholesale — the scripts
     call each other; `ci/README.md` documents what each one is)
   - `.gitleaks.toml`, `.pre-commit-config.yaml` → repo root; `CODEOWNERS` →
     the location the platform reads **first** if one is already in use
     (GitHub: `.github/`, then root, then `docs/`; GitLab: root, then
     `.gitlab/`, then `docs/`) — a second file in a lower-priority place owns
     nothing. Replace `@OWNER` with the gate's owner (from the project
     `CLAUDE.md`, else **ask**): the one identity the MR under check must not be.
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
   **Merge, never overwrite, a file that already exists:** `.gitlab-ci.yml`
   (add the `include:`), `.pre-commit-config.yaml` (add the payload's `repos:`
   entries and `default_stages`), `.gitleaks.toml` (add the `[[allowlists]]`
   block, keep theirs), `CODEOWNERS` (append the gate lines).

3. **Local layer:** tell the user to run `pip install pre-commit && pre-commit
   install` — the shipped config sets `default_install_hook_types`, so that one
   command wires both the pre-commit hooks and `ci/pre-push.sh` (the per-ref
   scan of commits about to leave the machine: amends, `commit --no-verify`,
   history from elsewhere). If the repo uses husky/lefthook (`git config
   core.hooksPath`), pre-commit's hooks are ignored — call `ci/pre-push.sh`
   from their pre-push hook instead and say so. Do not run global installs
   yourself. `bash ci/gate.sh --staged` runs the whole gate locally
   (`GATE_PINNED_ONLY=1` → the pinned scanner, not whatever is on `PATH`);
   `ci/scan-text.sh <file>` scans outgoing text (MR description, close
   comment) with the same rules — `task` phase 8 uses it.

3b. **Upgrading an existing gate** (`ci/gate.sh` already present — its version
   is the marker at the top of `ci/README.md`): replace `ci/` and its README,
   **merge** everything else (by `repo:`/hook `id:` in `.pre-commit-config.yaml`,
   by rule/allowlist name in `.gitleaks.toml`, by path in `CODEOWNERS`, keeping
   `variables:`/`env:` such as `MIGRATION_DIRS` and the coverage wiring in the
   CI file — show the diff before writing). Then redo step 5 (a payload that
   adds a gate job needs it added to the required contexts) and step 6. Going
   to 1.8.0, warn about the reason-bearing marker: `git grep -nE
   'destructive:[[:space:]]*approved([^(]|$)' -- <migrations dirs>` finds the
   markers that will start failing; committed migrations cannot be edited
   (forward-only), so they are fixed with the gate owner on the integration
   branch.

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

5. **Protected-branch + required code-owner review (one-time, per repo).**
   Force-push protection CANNOT be a CI job — by the time a pipeline runs, the
   push already happened. It is a platform rule, and so is the review rule that
   makes the `CODEOWNERS` approval on the gate files *required* (without it the
   MR under check can narrow a regex or widen an allowlist on its own). The
   exact commands for both platforms live in the copied
   `ci/README.md` → **Protected-branch (one-time, per repo)** — read them from
   the repo you just scaffolded, fill in owner/repo/branch, list every gate job
   the CI file defines as a required check, and offer to run them; confirm
   before executing, since they change repo settings (outward-facing). Two
   things to say out loud rather than assume: on GitLab
   `code_owner_approval_required` is **Premium** (on Free the file assigns
   reviewers and enforces nothing), and on a solo repo an author cannot approve
   their own MR — the owner picks a second account or knowingly skips the review
   rule (the file stays).

6. **Negative control — prove the gate can fail before trusting its pass.**
   Don't just run it green: run `bash ci/gate.sh --selftest`. It judges
   known-bad and known-good fixtures in a throwaway repo with *this* repo's
   scripts, scanner and `.gitleaks.toml` (unmarked drop, bare marker, marked
   drop, edited committed migration, broken `awk`, credential-shaped line,
   bidi override, ZWJ-emoji prose — list in `ci/README.md`). Read its output:
   a `warn` that none of `MIGRATION_DIRS` exists means the guard watches
   empty dirs. A gate nobody has seen fail is not known to work: a mis-set
   `MIGRATION_DIRS`, a scanner that never started and a genuinely clean diff
   all print the same thing. Exit codes: `0` ok · `1` policy violation · `2`
   config/infra (fails closed). Control the review rule the same way: a
   throwaway MR narrowing `SQL_RE` must ask for the gate owner's approval.
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
  fix the diff or add the explicit `-- destructive: approved (<ticket or
  reason>)` marker — the reason is mandatory, a bare marker fails.
- **The gate is not editable by the MR it judges.** `CODEOWNERS` + required
  code-owner review on the gate files is part of the scaffold, not an extra;
  without it the deterministic layer is as gameable as the LLM one. The
  implementer's account is never `@OWNER`.
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
  `# gitleaks:allow` on a one-off doc line over a global regex, and treat a
  **new** suppression in a change (an allow comment, a widened allowlist, a
  `-diff` line in `.gitattributes`, a narrowed pattern) as a review finding:
  each one turns a deterministic check off for the very diff it judges.
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
- **unicode-guard flags a deliberately small set** (bidi, zero-width
  space/joiner, mid-line `U+FEFF`, tag block) and never ZWJ/ZWNJ, LRM/RLM or
  soft hyphens — a guard that trips on prose gets switched off; don't widen it
  to "any non-ASCII". It matches bytes with `awk` under `LC_ALL=C`; a grep
  rewrite is fail-open on GNU grep.
- **pre-push fails closed:** a git failure or an unresolvable range blocks the
  push; the only bypass is `GATE_PREPUSH_SKIP="<sha>: <reason>"` naming the sha
  being pushed, logged to `.git/gate-bypass.log`. Never advise `git push
  --no-verify`; CI secret-scan is the backstop for that hole.
- **Ranges are validated before they are scanned.** gitleaks exits 0 when the
  git command inside it fails, and an empty word in `--log-opts` silently scans
  nothing; every scan also passes `--text` (a `-diff` attribute would hide a
  file) and `--diff-merges=first-parent` (a secret added in a merge commit is
  otherwise invisible). Keep all four when you touch a CI file.
- Never fetch and trust a `checksums.txt` alongside the binary in the same job —
  the committed SHA256 in `gitleaks-fetch.sh` is the trust anchor.
- On a shell runner, do **not** solve the docker dependency by adding the runner
  to the `docker` group — socket access there is host root. The pinned fetch
  exists precisely to avoid that.
- `dep/SCA` is language-specific and shipped as a commented stub — wire it to the
  repo's runtime (`npm audit` / `pip-audit` / `govulncheck` / …).
