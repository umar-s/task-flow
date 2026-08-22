# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The authoritative version lives in `.claude-plugin/plugin.json`; every release
below is tagged `vX.Y.Z` in git. Installs track the default branch (the
marketplace entry pins no ref), so a release tag marks history rather than a
download.

## [1.9.1] — 2026-08-22

### Fixed
- **`task` — when the post-review counting runs.** `implementation-integrity.md`
  §6 now says the "what changed since the review" commands run on the same
  `HEAD` the final fresh run was taken from — after the integration merge, not
  before it. Counting first and merging afterwards produced a true-looking `0`
  about a state that never shipped. (The last confirmed finding of the 1.9.0
  review; it landed after the tag, and `release-check` flagged the drift on CI
  — this release is that bump.)

### Added
- `README.md` / `README.ru.md`: a **Skill routing** snippet for the consuming
  project's `CLAUDE.md` — the skills' own descriptions compete with dozens of
  others in a session; a routing table is what makes the model reach for them.

## [1.9.0] — 2026-08-22

`task` — the third item of the donor-audit plan
(`docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md` §3.1 T1–T26, §4 O1/O2/O3/O5;
design in `docs/superpowers/specs/2026-08-22-task-flow-1-9-0-design.md`,
premortem panel over it in `docs/premortem/2026-08-22-task-1-9-0-premortem.md`).
Three classes of hole, all about **provability**: a verdict attached to nothing
checkable, irreversibility never named, and a phase 8 that stopped at "merged".

### Added
- **Four lazy references**, one per phase that needs it:
  `design-spec-template.md` (phase 1 — Problem / Scope / Context pack /
  Decisions / **Reversibility** / DoD→check table / Premortem edges / Failure
  signal, scaled by tier, with the rejection criteria that stop a rollback plan
  from being fiction); `blast-radius.md` (phase 3 — "an empty result is a
  claim", two searches in **different namespaces**, named blind spots, and the
  test-seam rules that used to sit in the skill); `land.md` (phases 7–8 — a
  merge command that exits non-zero is never retried, merge queues, the
  pipeline that already deploys, verification depth by scope, the `landing:`
  field, reverting **through this same flow**, and deleting only what you
  created); `checkpoint.md` (session hand-over — `<TASK-ID>.state.md` beside
  the spec, volatile facts carrying `⚠ VERIFY`/`⏱ TTL`, kept out of the task's
  diff, and validated against branch/HEAD before it is trusted).
- **Tier · type · reversibility** on one line in phase 0. The type shapes the
  first red test (bug → it reproduces the ticket's Actual and you locate the
  commit that introduced it; refactor → characterisation tests + mandatory
  mutation check); `one-way` (migration, persistent data, a public contract, a
  security boundary, a coordinated rollout) pulls in T3 artifacts whatever the
  tier says. **A tier only moves up**, and moving it up replays phase 1 and the
  premortem instead of relabelling the ticket.
- **DoD as a graded checklist:** `DoD-1..n` with a verifiability class
  (`diff | live | external`) proposed in phase 0 and settled in phase 8 by what
  was produced; the reviewer grades each item `PASS | FAIL | PARTIAL` with a
  `file:line` or command, and a PASS with nothing to point at is not a PASS.
- **A terminal status as the first line** of the close comment and of the
  skill's answer — `DONE | DONE_WITH_CONCERNS | BLOCKED | MERGED_NOT_LIVE |
  ABANDONED` — **derived from a table**, not chosen: `DONE_WITH_CONCERNS`
  names something the risk owner accepted, never an unfinished check. The
  tracker state follows it (Done only for the first two), and the landing
  detail is a separate `landing:` field so the two vocabularies share no token.
- **`Reviewed: <sha>` from the reviewer**, carried into the evidence block with
  `re-reviewed: yes|no` and the commands that compute "what changed since" —
  a merge of the integration branch reports `merge only` instead of a bare
  count that reads like a judgement.
- **Deploy / merge policy binding** (merge method, whether merging needs
  someone else's approval — asked once, never inferred from commit statistics —
  the authoritative MR-state command, the deploy trigger and its status check),
  and an optional Architecture-docs binding.

### Changed
- **The project ceiling is stated as what may be rebound** — commands, paths,
  branch names, environments, tools — and everything else (which phases run,
  their order, the clean-context review, "green includes the gate", the
  blocking force of Critical/Required, secrets out of the context) stands. A
  repo with no gate installed is a *state* (`gate: absent` in the evidence
  block plus an offer to scaffold), not a deviation.
- **A finding needs evidence, not a quote alone.** For "this line is wrong" it
  is `file:line` + the text; for an **absence** (no authz check, no test for a
  premortem edge, a missing grant, a consumer left on the old shape) it is the
  place it should have been plus the search proving it is nowhere else. This
  keeps the strongest class of finding from being downgraded by a rule meant to
  stop hand-waving.
- **The reviewer builds its own consumer list** at the reviewed sha, across two
  namespaces, and reports "no consumers" as a claim with its commands and blind
  spots. Scope is checked **both ways**: everything the DoD asks for, and
  nothing it did not.
- **Phase 6b triggers widened** to CI/CD and IaC files, container images,
  dependency manifests and the repo's own agent/skill/hook files, with the
  build-surface checklist (SHA-pinned actions, `pull_request_target`,
  `${{ github.event.* }}` in `run:`, secrets in job env).
- **Evidence is produced on the project's toolchain**, reported as a comparison
  (`node: pin 20.11.1 · actual 20.11.1 (match)`); a mismatch is not evidence.
- Orchestrator-facing review mechanics (severity → action, the
  behavioural/description split, one commit per fix, the verdict's sha) moved
  from the skill into the dispatch template that phase 6 already loads — the
  skill keeps the decision, the template keeps the method — as do
  `design-spec-template.md` (DoD classes, reversibility), `land.md` (the
  close-comment shape and scan-at-sink) and `implementation-integrity.md` (the
  status table, the toolchain comparison). After two review rounds added
  rules — `gate: absent` must carry the command that established it, the DoD
  class decides what counts as evidence, `landing:` is part of the comment —
  `task`'s prompt weight is **+27 % (2678 → 3411 words)** against the audit's
  22 % estimate; the four new references carry ~3.6k words that load one per
  phase.
- `decompose` may end a task's `context` with an advisory
  `risk tier: T1|T2|T3 — <why>`; it is a **floor, not a ceiling** for the
  tier `task` declares, and not a seventh field — the 6-field contract stands.
- `scripts/lint.sh` gained the new contracts as invariants (the status and
  landing vocabularies kept disjoint, `Reviewed:`, DoD grading, the tier
  ratchet, no `git add -A` in a skill, and the reverse of the reference check:
  a reference no phase loads is a defect), and the axiom greps are now
  whitespace-tolerant so a rewrap cannot drop one silently.

## [1.8.1] — 2026-08-22

Three findings from the completeness critic of the 1.8.0 review, all in the
shipped payload.

### Fixed
- **`GATE_BASE_REF` pointing at the tip switched off three layers at once.**
  A base that resolves to the same commit as `HEAD` makes every range empty, so
  `migration-guard`, `unicode-guard` and `diff-coverage` all reported OK on a
  change they never looked at — one CI variable, three green jobs.
  `ci/base-ref.sh` now fails closed on it ("that is not a base, it is an off
  switch"); an empty range from a *real* base still passes, as it should.
- **The shipped documentation still told consumers to validate a range with
  `git rev-list`** — the command 1.8.0 proved insufficient (it accepts diff
  options it never applies, so it cannot tell whether `git log`, which is what
  gitleaks runs, understands them). `ci/README.md`, both GitLab templates and
  the changelog entry now name the `git log --text --diff-merges=first-parent
  --max-count=1` form the code actually uses.

### Changed
- **`unicode-guard` reports how much of the change it scanned** — `N of M
  changed paths scanned (K excluded)` — and says outright when
  `UNICODE_GUARD_EXCLUDE` covered every changed path ("this run proves
  nothing"). The 1.8.0 probe only rejects catch-all patterns (`.`, `.*`); an
  anchored exclude listing a repo's own directories passes it, and the counters
  are what make that visible instead of silent.

## [1.8.0] — 2026-08-22

`ci-gate` hardening — the second item of the donor-audit plan
(`docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md` §3.3 G5–G11, G13; design in
`docs/superpowers/specs/2026-08-21-ci-gate-hardening-design.md`; the premortem
panel over that design is `docs/premortem/2026-08-22-ci-gate-hardening-premortem.md`). Three holes closed: the gate could be
edited by the MR it judges; text leaving the repo and commits leaving the
machine were never scanned; invisible code points in a diff had no layer at all.
Then the premortem found four ways the scans themselves reported "clean"
without having looked — each is fixed here, with a fixture that fails on 1.7.1.

### Added
- **`CODEOWNERS` in the payload** — `ci/`, `.gitleaks.toml`,
  `.pre-commit-config.yaml`, `.gitattributes`, the whole `.github/workflows/`
  directory and every location a `CODEOWNERS` file is read from, under the gate
  owner's review. (A required status check is matched by *name*, so a new
  workflow declaring a job called `secret-scan` could otherwise report a green
  check under the required name; and a higher-priority `CODEOWNERS` added in a
  later MR could own nothing.) The skill asks who owns the gate and writes the
  file where the platform reads it first; step 5 prints the *required*
  code-owner review rule with its GitLab-Premium and solo-repo caveats. This
  repo carries a `CODEOWNERS` too.
- **`ci/gate.sh --selftest`** — known-bad and known-good fixtures judged in a
  throwaway repo by the repo's own scripts, scanner and `.gitleaks.toml`:
  unmarked drop, marker without a reason, marked drop, edited committed
  migration, broken `awk`, credential-shaped line, bidi override, ZWJ-emoji
  prose, plus a warning when none of `MIGRATION_DIRS` exists and when no
  **executable** pre-push hook is installed (a hook file without `+x` is one
  git ignores silently). The repo's git config cannot break it
  (`GIT_CONFIG_GLOBAL=/dev/null`, empty template, no gpg signing, no
  `core.hooksPath`). The skill's negative control (step 6) is now this command.
- **`ci/unicode-guard.sh`** — added lines must not carry bidi
  overrides/isolates, zero-width space / word joiner, a mid-line `U+FEFF` or
  Unicode tag characters (Trojan Source). ZWJ/ZWNJ, LRM/RLM and soft hyphens
  are deliberately not flagged; one line can carry `unicode-guard:allow`.
  Matches bytes with `awk` under `LC_ALL=C` and **self-probes that awk first**
  (GNU grep in the C locale silently fails on byte ranges ≥ 0x80 — a clean
  verdict it never established). Its `git diff` pins every knob that could
  empty its input: `--text` (a `-diff` attribute in `.gitattributes`),
  `--no-ext-diff`, `--no-textconv`, `--no-color`, fixed prefixes. Wired into
  `gate.sh`, pre-commit and all three CI templates as a job, and run over this
  repository's own changes in `check.yml`.
- **`ci/pre-push.sh`** — per-ref secret-scan of the commits a push actually
  sends: `remote..local` when the remote sha is known here, otherwise
  `local --not --remotes=<remote>` (which also covers commits sitting unpushed
  on another local branch — a merge-base against the default branch missed
  those). The range is validated before the scan with the same `git log`
  invocation the scan runs, because
  gitleaks exits 0 when the git command inside it fails. Runs through
  pre-commit or as the native hook. Bypass only with
  `GATE_PREPUSH_SKIP="<sha>: <reason>"` naming the sha being pushed — a value
  left in a shell profile does not bypass the next push — and it is logged to
  `.git/gate-bypass.log`.
- **`ci/scan-text.sh <file>`** — one file scanned with the gate's scanner and
  rules before its text is posted; `task` phase 8 writes the close comment / MR
  description to a file, scans it and posts that same file. A gitleaks exit 1
  with no report is a configuration error, not a finding — it fails closed.
- **`ci/gitleaks-bin.sh` and `ci/base-ref.sh`** — one place each for "which
  scanner runs" and "what counts as this change"; `gate.sh`, `scan-text.sh`,
  `pre-push.sh`, `migration-guard.sh`, `unicode-guard.sh` and
  `diff-coverage.sh` now call them instead of carrying copies.
- **macOS support in `gitleaks-fetch.sh`** — committed SHA256s for
  `darwin_{x64,arm64}` next to the Linux pair, and an explicit fail-closed
  message on any other platform (it used to download a Linux tarball and hand
  back a binary that cannot run — which, with the new pre-push layer, would
  block every push from a mac).
- **`ci/README.md`** — "When secret-scan fires" (revoke first, size the window,
  rewrite the branch or scrub history with the protection lifted on the record,
  audit, never allowlist), an inventory of `ci/`, an "Upgrading the payload"
  section, and "Known limits — the whole gate": `gitleaks:allow` as the cheapest
  bypass, `.gitattributes` blinding the local `protect --staged` path,
  homoglyphs, `pre-push` being advisory, and the `--log-opts` landmines.
- **Repository tests**: `tests/unicode-guard.sh` (fixtures × gawk/mawk/busybox),
  `tests/pre-push.sh` (amend, unknown remote sha, unpushed work on another
  branch, evil merge, `-diff` attribute, unresolvable range, broken git, broken
  scanner, stale bypass, native hook via `git push`), `tests/scan-text.sh`,
  `tests/gate-selftest.sh` (the selftest goes red when a regex is emptied, the
  marker check relaxed, the allowlist widened or unicode-guard neutered).
  `tests/run.sh` now globs `tests/*.sh`, and `scripts/lint.sh` checks the
  payload is one set: one scanner resolution, one base-ref resolution, `--text`
  and `--diff-merges=first-parent` on every range scan, the `${RANGE:+ …}` form,
  no credential-shaped literal in any tracked file, the payload version marker,
  and the documented marker form matching the one the guard accepts.

### Changed
- **`migration-guard`: the marker must carry a reason.** `-- destructive:
  approved (<ticket or reason>)` — a bare `-- destructive: approved`,
  `approved ()` or `approved (  )` now **fails** with a message showing the
  form. MRs in flight with a bare marker will start failing; `ci/README.md` →
  "Upgrading the payload" has the `git grep` that finds them.
- **`migration-guard`: an empty `MIGRATION_DIRS` is `exit 2`**, not "skipping".
  A blank CI variable used to switch the whole layer off from the settings UI
  and leave a green job that inspected nothing. `migrations/`, `./migrations`
  and `/migrations` now all mean the same directory (a trailing slash used to
  build a pattern that matches nothing), and an entry that normalises to
  nothing is a config error.
- **`migration-guard` reads the change set NUL-delimited** (`--raw -z`): a path
  git prints in C-quotes (a quote, a backslash or a tab in the name) used to
  fall outside the migrations pattern and skip both policies. The same raw
  format carries the file mode, so a migration added as a **symlink** now fails
  — its blob is the target path, and the file that actually runs is elsewhere.
- **`unicode-guard` rejects an exclude that matches every path** (`.`, `.*`)
  with exit 2, and its diff parser now treats `+++`/`@@`/`diff --git` as
  headers only outside a hunk: an added line whose text begins with `++ `
  arrives as `+++ …` and used to end the hunk, hiding every line after it.
  `ci/diff-coverage.sh` had the same parser bug — later hunks of a file
  silently left the coverage denominator — and now counts hunk lines too.
- **Every payload layer pins `LC_ALL=C`.** Case folding is locale-dependent: in
  a Turkish or Azerbaijani locale `grep -i` does not fold `i`/`I`, so a
  lowercase `drop index`, `drop constraint` or `drop trigger` stopped matching
  and the migration passed without a marker.
- **`unicode-guard` strips NUL bytes before awk.** busybox awk — the awk in the
  alpine image the CI templates use — splits a record at a NUL, and the tail
  (exactly where bytes would be hidden) no longer looks like an added line, so
  it was never scanned. Both halves of that pipeline are now checked: a failing
  `tr` is `exit 2`, not an empty scan that reads as clean.
- **Every range scan validates itself with the command gitleaks runs**
  (`git log --text --diff-merges=first-parent --max-count=1 …`). `git rev-list`
  accepts diff options it never applies, so it could not tell that a git older
  than 2.31 would fail inside gitleaks — which reports "no leaks found" and
  exits 0. The payload now needs git ≥ 2.31 and says so.
- **Every git-range secret-scan** (three CI templates, `pre-push.sh`,
  `gate.sh`, this repo's own `check.yml`) now passes
  `--text --diff-merges=first-parent` and validates the range with
  the same `git log` invocation first. Without them a `-diff` line in
  `.gitattributes` hid a
  file from the scan, a secret added in a merge commit was invisible, and a
  range git could not resolve was reported as "no leaks found".
- **`unicode-guard` is active, not opt-in**, and belongs in the required status
  checks — a layer wired in halfway is green by omission.
- `.pre-commit-config.yaml` sets `default_install_hook_types: [pre-commit,
  pre-push]`, so the usual `pre-commit install` wires the pre-push layer too,
  and `default_stages: [pre-commit]` keeps the other hooks off that stage.
  It declares `minimum_pre_commit_version: '3.2.0'` — the release where the
  `pre-commit`/`pre-push` stage names exist; on 2.18–3.1.x the file fails
  schema validation on every run.
- **`ci/gitleaks-fetch.sh` takes `GITLEAKS_URL_BASE`** so a shop without egress
  to github.com can mirror the pinned tarball internally; the committed SHA256
  still decides whether what came back is the pinned build. `gate.sh` maps a
  scanner it could not resolve to exit 2 (it used to surface curl's exit code,
  which a wrapper reads as neither "violation" nor "infra").
- **The skill's install and upgrade instructions match what the tools do**:
  `pre-commit install` *refuses* to run when `core.hooksPath` is set (husky,
  lefthook) — the recipe for those is spelled out; a pre-commit `entry` runs
  without a shell, so `MIGRATION_DIRS=…` there needs `env`; an upgrade takes
  the gate jobs' `script:` blocks from the payload verbatim (keeping only
  `variables:`/`rules:`/`tags:`/`needs:`), because a merged CI file that keeps
  the old block keeps the old fail-open scan — and it re-runs steps 3, 5 and 6.
  The reason-bearing marker only bites migrations an MR *adds*: a release MR
  presents everything merged since the last release as added, which is when a
  bare marker fails and a committed migration can no longer be edited.
- `ci-gate` skill: step 2 merges into existing `.pre-commit-config.yaml`,
  `.gitleaks.toml` and `CODEOWNERS` instead of overwriting and copies `ci/`
  wholesale; new step 3b covers upgrading a gate that is already installed;
  step 5 now points at the commands in the vendored `ci/README.md` rather than
  repeating them.
- `task` phase 8 names the gate jobs from the repo's own CI file (not a list
  memorised in the skill), spells out what `scan-text.sh` rc 1 / rc 2 mean, and
  the fixed discipline forbids `--no-verify` and `GATE_PREPUSH_SKIP` for the
  agent: a blocked push is a finding, and bypassing a gate is the user's call.
- `security-review-prompt.md`: the destructive marker is a declaration by its
  author, not an approval; a new suppression in the diff (allow comment,
  widened allowlist, `-diff` attribute, narrowed gate pattern) and
  mixed-script identifiers are findings.

## [1.7.1] — 2026-08-21

Defects in our own files, surfaced by the donor audit of a colleague's toolkit
(`docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md`, §2), then by two
clean-context reviews of the fix. No new plugin behaviour — every item makes an
existing promise actually hold.

### Added
- **Repository scripts and tests** (not part of the plugin): `scripts/lint.sh`
  turns the written rules of this repo into greps (reference links resolve,
  `$ROOT` block present, no fail-open idioms in the payload, decompose
  vocabulary consistent across its five files, one scanner version and one
  image digest in every path, no tag-pinned actions, no personal paths in
  tracked files); `scripts/release-check.sh` checks the four-step release
  ritual and classifies the tree as unreleased / released / drifted;
  `scripts/readme-parity.sh` keeps `README.md` and `README.ru.md`
  structurally in lockstep; `tests/` holds the payload's negative controls —
  51 migration-guard fixtures, run again under busybox awk/grep where
  available (default reversible templates of Laravel, Knex, Sequelize,
  TypeORM, Rails, Alembic must pass; drops in the forward part, helpers after
  `down`, bypass layouts, nested `down` look-alikes, files over 64 KB must
  not), two tool-failure controls (a broken `awk` or `grep` is `exit 2`), and
  the failure paths of `gitleaks-fetch.sh`. `.github/workflows/check.yml` runs
  them, actionlint and yamllint (both pinned), and the product's own
  secret-scan over this repository.
- **`ci-gate` — `gate.sh`** accepts `GATE_PINNED_ONLY=1` to ignore a `gitleaks`
  on `PATH` and use the pinned one (the verdict CI will give).

### Changed
- **`ci-gate` — `migration-guard.sh` judges the forward part of a migration,
  and detects more there — MRs in flight may start to need the marker.** The
  body of a `down` / `downgrade` block that follows an `up` / `upgrade` /
  `change` definition at the same indentation is skipped; everything else —
  helpers after it, a redefined `up`, files without an `up` (plain SQL,
  `*.down.sql`, `-- +goose Down` sections, Django) — is scanned. A conventional
  reversible migration in one file (Rails, Alembic, Laravel, Knex, Sequelize,
  TypeORM — in DSL or in SQL) no longer needs the marker. SQL: `DROP` of a
  view, type, sequence, trigger, function, procedure or materialized view and
  `ALTER TABLE … DROP <anything>` (the `COLUMN` keyword is optional in
  PostgreSQL/MySQL) now count as destructive. ORM: the table/column-dropping
  DSL tokens of the frameworks whose directories are scanned by default
  (Rails/Alembic, Django, Laravel, Knex/Sequelize/TypeORM) are matched
  case-sensitively, as whole words. A failing `awk`/`grep` is `exit 2`, never
  a pass, and files larger than a pipe buffer are judged, not skipped. The
  residue — multi-line statements, SQL assembled from strings, `DELETE`
  without `FROM`, lossy type changes, constraint-dropping DSL calls, unlisted
  DSLs, deliberate evasion through indentation — is documented as "Known
  limits" in `ci/README.md` and handed to the phase-6b security review
  explicitly.

### Fixed
- **`task`** — reference files are now loaded through a resolved `$ROOT`
  (`CLAUDE_PLUGIN_ROOT`, with a fallback), the same block `decompose` already
  had; the three phase references were plain relative links, which the Read
  tool cannot follow from an installed plugin, so a phase could silently run
  from memory of the reference instead of the reference. A failed Read now
  stops the phase.
- **`task` phase 8** — "CI green including the gate" now means *present and
  passed*: confirm the gate jobs actually ran on this MR and name them in the
  evidence block. A pipeline that never scheduled them is green by omission.
- **`ci-gate` — one scanner version in every path.** The GitLab docker/k8s
  and GitHub templates pulled `ghcr.io/gitleaks/gitleaks:latest`, so the pin
  policy held only on the shell runner; both now pin the image by digest at
  the same version as `PIN_VERSION`. `.pre-commit-config.yaml` pins `rev` to
  the release commit (a tag is re-pointable) and no longer recommends
  `pre-commit autoupdate`. GitHub actions are pinned by commit SHA.
- **`ci-gate` — `gitleaks-fetch.sh`** verifies a private copy of the cached
  tarball against the committed SHA256 on every call and extracts that copy
  into a per-call dir; a cached binary in a shared runner cache was previously
  executed unverified after the first download. The cache is an optimisation
  (unreadable or read-only → re-download, never a failed job); the per-call
  dir is removed by the caller (`gate.sh` traps it; the shell CI variant sets
  `GITLEAKS_RUN_DIR` to the job workspace and cleans it in `after_script`).
- **`ci-gate` — `.gitleaks.toml`** allowlist reduced to the path block, in the
  `[[allowlists]]` form. With `regexTarget = "line"` a placeholder anywhere on
  a line excused a real secret beside it, and the unanchored AWS example
  literals — already excluded by the default ruleset — suppressed any
  generic-api-key span that merely contained them.
- **GitHub template** — event data reaches `run:` steps through `env:` rather
  than inlined `${{ }}`; a branch name can carry shell metacharacters, so
  `github.base_ref` inlined into `run:` was a real vector for anyone able to
  create a branch. The repository is mounted read-only into the scanner
  container.

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

[1.9.1]: https://github.com/umar-s/task-flow/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/umar-s/task-flow/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/umar-s/task-flow/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/umar-s/task-flow/compare/v1.7.1...v1.8.0
[1.7.1]: https://github.com/umar-s/task-flow/compare/v1.7.0...v1.7.1
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
