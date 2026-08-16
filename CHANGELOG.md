# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The authoritative version lives in `.claude-plugin/plugin.json`; every release
below is tagged `vX.Y.Z` in git. Installs track the default branch (the
marketplace entry pins no ref), so a release tag marks history rather than a
download.

## [1.7.0] — 2026-08-17

### Added
- **`ci-gate` — `ci/diff-coverage.sh`**: a changed-line coverage threshold. It
  judges a report the project's own test run produced (lcov / Cobertura /
  Clover, auto-detected; minified XML and absolute report paths handled) and
  gates only the lines the change touched, because a global percentage moves
  too slowly to notice an untested change. Fails closed on a missing, empty or
  unparseable report, an unresolvable base ref, or a non-integer threshold;
  skips itself (loudly) while `GATE_COVERAGE_REPORT` is unset;
  `GATE_COVERAGE_STRICT=1` turns "nothing measurable" into a failure. Wired
  into `gate.sh` and shipped commented-out in the GitLab (docker + shell) and
  GitHub templates.
- **`task`** — property-based testing where invariants exist, with the
  one-sided-invariant trap called out; the reproduction-command rule for every
  number reported.

### Changed
- **`task`** — the mutation check must be scoped by diff, with per-tool filters
  (Infection, Stryker, mutmut, cargo-mutants, PIT); a local run is acceptable
  when CI is too slow, and survivors in legacy code outside the diff are
  backlog rather than a blocker.
- **`task` phase 8** — the "что сделано" comment becomes an evidence block:
  numbers from one final fresh run made after the last edit, the command that
  reproduces them, and every skipped check named with its reason.

## [1.6.0] — 2026-08-17

Donor audit of `AmazingAng/old-coder` (evidence-first development) —
`docs/audits/2026-08-17-old-coder-donor-audit.md`.

### Added
- **`task` phase 0** — a declared blast-radius tier (trivial / normal /
  high-stakes) that scales the *artifacts* and never the gates, plus the rule
  that a phase which finds nothing says so. Invented risk becomes an invented
  requirement, which is how a heavy flow damages a small change.
- **`skills/task/references/implementation-integrity.md`** — the phase-5 floor:
  baseline on a repo that is not already green, RED means you watched it fail,
  five anti-gaming rules, a mutation check on the changed logic, suite health,
  and numbers-not-adjectives reporting.
- **`task` phase 6b** — the capability diff (did the change start reaching the
  network, subprocesses, the filesystem, or new credentials?).
- **`ci-gate`** — the smoke-check becomes a negative control: prove the gate can
  fail before trusting a pass. Gate code must fail closed (no `|| true`, no
  `2>/dev/null`, ambiguous exit codes spelled out).
- `skills/task/NOTICE.md` — attribution and the trust-model delta.

### Changed
- **`task` phase 6** — findings are graded behavioural vs description, so the
  re-review loop terminates; a verdict attaches to the commit it saw, and fixes
  made after it ship an unreviewed state unless re-reviewed or declared.
- **`decompose` phase 6** — an answer to a question you asked is not an approval
  of the draft.

### Fixed
- **`migration-guard`** — a fail-open found by applying the new rule to our own
  code: an unreadable entry under a migrations directory produced empty content,
  the destructive-DDL scan found nothing, and the guard printed `OK`. It now
  exits 2. Verified on a live repo (staged gitlink: `OK`/0 before, fail-closed/2
  after), with no regression on the three policy cases.

## [1.5.0] — 2026-08-16

Donor audit of the `hybrid-plan` / `hybrid-review` skill set —
`docs/audits/2026-08-16-hybrid-vs-task-flow.md`.

### Added
- **`task`** — frontier question selection (phase 0); a blast-radius map with
  risk-first ordering and an explicit test-seam choice (phase 3); severity →
  action semantics and a conditional `superpowers:receiving-code-review` bridge
  (phase 6).
- **Review prompts** — evidence honesty, a verification-assessment section, a
  residual-risk section for the security pass, a no-subagent / no-secrets
  sandbox, and `git status --short` inside the review scope so a forgotten
  `git add` is a finding.
- **`decompose`** — expand → migrate → contract as the splitting axis for wide
  incompatible changes; QA Check 8 (wave parallelism safety); risks and open
  questions in the draft, with no blocking question surviving approval.

### Changed
- **`decompose` phase 4** — waves are validated against shared-write collisions,
  not only against `depends_on`.
- Both skills — the project's `CLAUDE.md` outranks the flow, and a deviation is
  declared rather than silent.

## [1.4.1] — 2026-08-10

### Changed
- **`task`** — premortem edge cases feed the phase-6 review dispatch only. The
  6b security pass walks the trust boundaries itself instead of inheriting the
  team's worry list.

## [1.4.0] — 2026-08-10

### Added
- A conditional escalation bridge to the `premortem` skill: offered in `task`
  phase 2 for high-risk designs and in `decompose` phase 6 for large or risky
  epics, never forced, with the resulting artifact folded back into the flow.

## [1.3.0] — 2026-08-10

### Added
- **`task`** — structural review dispatch: the reviewer and security prompts
  move into `references/` as clean-context templates, with read-only and
  worktree rules, reviewer calibration, PoC-gated severity, and a fresh review
  of every fix delta.

## [1.2.2] — 2026-07-19

### Changed
- **`decompose`** — QA runs until a clean check-run instead of stopping at a
  cycle count. The cap becomes a runaway backstop with an explicit
  non-convergence escalation.

## [1.2.1] — 2026-07-19

### Added
- **`decompose`** — QA cap-exhaustion escalation: an `UNVERIFIED` flag on fixes
  no check-run has cleared, plus a targeted re-check offer.

## [1.2.0] — 2026-07-18

### Added
- **Third skill: `decompose`** — a 7-phase flow turning an epic, feature
  description or spec into dependency-linked tasks (6 author fields, `dod` with
  `truths`, story points, `depends_on` graph, parallelism waves), reviewed by an
  independent QA subagent, written as a self-contained MD draft, with an
  optional dry-run-first tracker push. References for SPIDR splitting,
  edge-probe, thinking models, the task schema, the QA checklist, the draft
  template and tracker sync; `NOTICE.md` credits Open GSD.

## [1.1.0] — 2026-07-17

### Added
- **`ci-gate`** — a GitLab shell-executor variant (no docker, no runner
  changes), and `ci/gitleaks-fetch.sh`: a pinned, arch-aware gitleaks fetch
  verified against a committed SHA256, failing closed on mismatch.

### Changed
- Secret-scan is incremental — MR range, new commits on a default-branch push
  (with a zero-SHA full-scan fallback), full history on a scheduled pipeline.
- Tight gitleaks allowlist; pre-commit gitleaks pinned to the same version.

## [1.0.0] — 2026-07-17

### Added
- Initial release with two skills. **`task`**: ingest → 2× premortem → TDD →
  code-review → conditional security-review → live verify → close, with the CI
  gate green before merge. **`ci-gate`**: scaffolds a gitleaks secret-scan, a
  tool-agnostic migration-guard and protected-branch rules into any repo —
  GitLab and GitHub CI, pre-commit hooks, failing closed.

[1.7.0]: https://github.com/umar-s/task-flow/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/umar-s/task-flow/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/umar-s/task-flow/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/umar-s/task-flow/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/umar-s/task-flow/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/umar-s/task-flow/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/umar-s/task-flow/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/umar-s/task-flow/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/umar-s/task-flow/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/umar-s/task-flow/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/umar-s/task-flow/releases/tag/v1.0.0
