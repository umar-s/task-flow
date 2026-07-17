# task-flow

A Claude Code plugin: a disciplined **per-task quality flow** plus the
**deterministic CI gate** it leans on. Two skills, one product.

> Русская версия — [README.ru.md](README.ru.md).

## Skills

### `task` — per-task quality flow
Takes one tracked ticket from ingest to closed through fixed quality gates:

```
0 ingest → 1 design-spec → 2 premortem(design) → 3 plan → 4 premortem(plan)
→ 5 TDD → 6 code-review → 6b security-review* → 7 verify live → 8 close
```

`*` conditional: the security pass runs only when the diff touches auth, input,
network, secrets, data/PII, migrations, or grants. It is the **LLM** layer —
gameable and correlated with the implementer — so it never replaces the
deterministic gate below, and vice versa. One task = one branch → one MR/PR,
CI green (including the gate) before merge.

Invoke with `/task DEV-475` (or "прогони через наш flow"). The discipline is
fixed; concrete tracker/VCS/build commands are resolved from the project's
`CLAUDE.md`.

### `ci-gate` — scaffold the deterministic merge gate
Drops a portable, non-gameable gate into any repo — the floor under the
blast-radius categories tests and LLM review miss:

- **secret-scan** — gitleaks, in pre-commit and CI
- **migration-guard** — tool-agnostic, path-based: forward-only immutability +
  destructive DDL requires an explicit `-- destructive: approved` marker
- **protected-branch** — no force-push + required status checks (platform rule,
  set once via `glab`/`gh`)

Invoke with `/ci-gate` in a repo. It copies `ci/`, the gitleaks + pre-commit
config, the GitLab **or** GitHub CI file, and prints the protected-branch
commands. Template payload lives in `templates/ci-gate/`.

Executor-aware for GitLab: a **docker/k8s** variant (uses `image:`) and a
**shell** variant that fetches a pinned, checksum-verified gitleaks in-job — no
docker, no runner change, no docker-group escalation. Secret-scan is incremental
(MR range / new commits on push / full-history on a schedule).

## Install

```
/plugin marketplace add umar-s/devpowers
/plugin install task-flow@devpowers
```

## Design notes
- The gate is deterministic on purpose: an LLM reviewer optimizes for "green",
  not "correct", and shares blind spots with the implementer. Secrets and
  destructive migrations get a non-gameable check; logic gets the LLM pass.
- `dep/SCA` ships as a commented stub — language-specific, wire it per repo.
- migration-guard fails **closed** (exit 2) if it cannot resolve the base ref in
  CI — a guard that silently passes is worse than none.

MIT © Sergei (umar-s)
