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

1. **Confirm target + platform.** Run from the repo root (`git rev-parse
   --show-toplevel`). Detect the CI platform: `.gitlab-ci.yml` → GitLab,
   `.github/` → GitHub. If ambiguous, ask.

2. **Copy the payload** from `${CLAUDE_PLUGIN_ROOT}/templates/ci-gate/`:
   - `ci/` (migration-guard.sh, gate.sh, README.md) → `<repo>/ci/`
   - `.gitleaks.toml`, `.pre-commit-config.yaml` → repo root
   - **GitLab:** `gitlab/ci-gate.gitlab-ci.yml` → `<repo>/ci/ci-gate.gitlab-ci.yml`,
     then add `include: [ { local: 'ci/ci-gate.gitlab-ci.yml' } ]` to the
     project `.gitlab-ci.yml` (create if absent).
   - **GitHub:** `github/gate.yml` → `<repo>/.github/workflows/gate.yml`.
   - `chmod +x ci/*.sh`.
   Do not overwrite an existing project `.gitlab-ci.yml` — merge the `include:`.

3. **Local layer:** tell the user to run `pip install pre-commit && pre-commit
   install` so secrets are caught before push. Do not run global installs yourself.

4. **Configure migration dirs** if the repo's migrations are not under a default
   (`migrations db/migrate db/migration prisma/migrations`): set `MIGRATION_DIRS`
   in the CI job env and the pre-commit hook `entry`.

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

6. **Smoke-check** without waiting for CI: `bash ci/gate.sh --staged` on a
   throwaway staged change. `migration-guard` exit codes: `0` ok · `1` policy
   violation · `2` config/infra (fails closed).

## Guardrails
- The gate is a floor, not a lint pass — never weaken a rule to make a diff pass;
  fix the diff or add the explicit `-- destructive: approved` marker with a reason.
- Keep the gitleaks allowlist tight — every entry is a hole in the gate.
- `dep/SCA` is language-specific and shipped as a commented stub — wire it to the
  repo's runtime (`npm audit` / `pip-audit` / `govulncheck` / …).
