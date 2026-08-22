# task-flow

[![version](https://img.shields.io/github/v/release/umar-s/task-flow?label=version&color=0b7285)](https://github.com/umar-s/task-flow/releases/latest)
[![changelog](https://img.shields.io/badge/changelog-keep--a--changelog-0b7285)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-0b7285)](LICENSE)

A Claude Code plugin: a disciplined **per-task quality flow** plus the
**deterministic CI gate** it leans on — and a `decompose` skill that feeds
both. Three skills, one product.

> Русская версия — [README.ru.md](README.ru.md).
> Release history — [CHANGELOG.md](CHANGELOG.md).

## Pipeline

```
decompose → task → ci-gate
```

`decompose` cuts an epic/feature/spec into tasks; each task runs the `task`
flow end-to-end; `ci-gate` is the deterministic floor every merge goes
through.

## Skills

### `decompose` — epic/feature/spec → task breakdown
Turns one large unit of work — a free-text feature description, an existing
tracker epic `<TASK-ID>`, or a spec/design doc — into well-formed,
dependency-linked tasks with a full **6-field** contract (`name`, `context`,
`requirements`, `dod` with `truths`, `story_points`, `depends_on`), a
`depends_on` graph, and computed parallelism waves:

```
0 ingest → 1 requirements → 2 decompose → 3 enrich → 4 graph/waves
→ 5 QA (fresh-context subagent) → 6 MD draft → 7 tracker sync*
```

`*` optional: Phase 7 only runs after explicit approval of the draft, always
dry-run-first, and stops gracefully at the draft if no tracker is configured —
and when it does write, it **reads every issue back** and compares it with what
was sent, because an `ok` from the writing side is a claim, not a check.
The QA pass judges fields on quality, not just presence: a goal verb with no
artifact, an adjective with no metric, an open-ended list or a path that does
not exist are findings, and an identifier nobody could confirm is written as a
`<placeholder>` rather than invented.
Story Points use Fibonacci (`1/2/3/5/8/13`) as an **optional annotation, not a
gate** — splitting is driven by SPIDR/vertical-slices/dependencies. The MD
draft (`docs/decompose/YYYY-MM-DD-<epic>.md`) is the self-contained primary
artifact; tracker push (YouTrack and other adapters) is a generic, optional
extra.

Invoke with `/decompose` (or "нарежь на задачи", "декомпозируй эпик"). Each
produced `<TASK-ID>` is then picked up end-to-end by `task`.

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

Each task declares **tier · type · reversibility** (a tier only moves up), each
DoD item is graded `PASS | FAIL | PARTIAL` against a `file:line` or a command,
and the close comment opens with a terminal status — `DONE |
DONE_WITH_CONCERNS | BLOCKED | MERGED_NOT_LIVE | ABANDONED` — so a human, or a
runner, reads the outcome without parsing prose.

Invoke with `/task DEV-475` (or "прогони через наш flow"). The discipline is
fixed; concrete tracker/VCS/build commands are resolved from the project's
`CLAUDE.md`.

With the `prediction-protocol` plugin installed, `task` puts the session under
the prediction gate at the start of phase 5 (`predict-gate: active`), turns
every state-changing step — migrations on dev, merge, deploy, each `live` DoD
item — into a receipt graded by the tool, reads `docs/evidence/REFUTED.md` in
phase 0, and carries the `predictions:` line into the evidence block. Without
the plugin the same lines print `predict-gate: absent` and the flow runs as
before.

### `ci-gate` — scaffold the deterministic merge gate
Drops a portable, non-gameable gate into any repo — the floor under the
blast-radius categories tests and LLM review miss:

- **secret-scan** — gitleaks, in pre-commit, pre-push and CI; pre-push scans
  the commits about to leave the machine, per ref (catches `--no-verify`,
  amends, history from elsewhere), and blocks when git cannot tell what is
  being pushed
- **migration-guard** — tool-agnostic, path-based: forward-only immutability +
  destructive DDL requires an explicit `-- destructive: approved (<reason>)`
  marker — the reason is mandatory; a migration added as a symlink fails (its
  blob is the target path, not the SQL that runs)
- **unicode-guard** — no bidi overrides, zero-width or tag characters in
  added lines (Trojan Source); ordinary non-ASCII prose and emoji never trip it
- **diff-coverage** — changed-line coverage threshold, opt-in: reads the report
  the project's own test run produced (lcov / Cobertura / Clover), judges only
  the lines this change touched
- **protected-branch** — no force-push + required status checks + required
  code-owner review on the gate files (`CODEOWNERS`): the MR under check cannot
  edit the judge (platform rule, set once via `glab`/`gh`)

Invoke with `/ci-gate` in a repo. It copies `ci/`, the gitleaks + pre-commit
config, `CODEOWNERS`, the GitLab **or** GitHub CI file, and prints the
protected-branch commands. `ci/gate.sh --selftest` then proves the gate can
fail — known-bad fixtures judged by this repo's own scripts, scanner and
allowlist — before anyone trusts its green; `ci/scan-text.sh <file>` scans a
comment or MR description before it is posted. Template payload lives in
`templates/ci-gate/`.

Host requirements: `bash` 3.2+, `git` **2.31+** (a scan without
`--diff-merges` is blind to secrets added in a merge commit — the layers refuse
to run rather than scan less than they promise), any awk, and `pre-commit`
3.2.0+ for the local hooks.

Executor-aware for GitLab: a **docker/k8s** variant (uses `image:`) and a
**shell** variant that fetches a pinned, checksum-verified gitleaks in-job — no
docker, no runner change, no docker-group escalation. One scanner version in
every path: image digest in the docker/GitHub jobs, committed SHA256 on the
shell runner (re-verified on every call), commit-pinned `rev` in pre-commit.
Secret-scan is incremental (MR range / new commits on push / full-history on a
schedule).

## Install

```
/plugin marketplace add umar-s/devpowers
/plugin install task-flow@devpowers
```

Then drive the pipeline: `/decompose` an epic into tasks, `/task DEV-475` each
one through the quality flow, `/ci-gate` once per repo to scaffold the merge
gate they all land behind.

## Skill routing (paste into the consuming project's `CLAUDE.md`)

The skills' own `description`s compete with dozens of others in a session; a
routing table in the project's `CLAUDE.md` is what makes the model reach for
them on its own:

```markdown
## Skill routing
- A ticket / task id (`DEV-475`, `#123`, "сделай задачу …") → `/task`
- An epic, a feature description or a spec to slice into tasks → `/decompose`
- "add the CI gate", "secret scan", "migration guard", a new repo → `/ci-gate`
- Unsure whether a skill applies → invoke it; declining inside the skill is
  cheaper than a flow run without it.
```

## Design notes
- The gate is deterministic on purpose: an LLM reviewer optimizes for "green",
  not "correct", and shares blind spots with the implementer. Secrets and
  destructive migrations get a non-gameable check; logic gets the LLM pass.
- Ceremony scales, gates don't: `task` phase 0 declares a tier (trivial /
  normal / high-stakes) that sizes the **artifacts**, never the phases. A phase
  that finds nothing says so — an invented risk becomes an invented
  requirement, and on a small ticket that is the likeliest way a heavy flow
  damages the change instead of protecting it.
- `dep/SCA` ships as a commented stub — language-specific, wire it per repo.
- migration-guard fails **closed** (exit 2) when it cannot resolve the base ref
  in CI, or cannot read a migration it is supposed to judge — a guard that
  silently passes is worse than none. Prove it can fail before trusting a pass.

MIT © Sergei (umar-s)
