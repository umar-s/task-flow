# ci-gate (vendored)

<!-- ci-gate payload version: 1.8.0 — `/ci-gate` re-run upgrades it; see "Upgrading" -->

Deterministic merge gate for this repository — the non-gameable floor under
secrets, destructive migrations, and force-push. It complements (does not
replace) unit tests and LLM review.

| Layer | What | Where |
|---|---|---|
| **secret-scan** | gitleaks — secret in the diff/history | pre-commit + pre-push + CI |
| **migration-guard** | forward-only + destructive DDL needs a marker with a reason | pre-commit + CI |
| **unicode-guard** | no invisible / direction-overriding code points in added lines (Trojan Source) | pre-commit + CI |
| **diff-coverage** | changed lines actually executed by a test, above a threshold | CI (opt-in) |
| **scan-text** | one file scanned before its text leaves the repo (MR description, close comment) | `ci/scan-text.sh` on demand |
| **protected-branch** | no force-push, required status checks, **required code-owner review on the gate files** | platform rule (set once) + `CODEOWNERS` |

## What is in `ci/`
| Script | Runs | Verdict |
|---|---|---|
| `gate.sh` | locally (`--staged`, `--selftest`) | runs every layer below; `--selftest` proves they can fail |
| `migration-guard.sh` | pre-commit + CI | forward-only + destructive DDL marker |
| `unicode-guard.sh` | pre-commit + CI | invisible / bidi code points in added lines |
| `pre-push.sh` | pre-push hook | secret-scan of the commits a push sends |
| `scan-text.sh` | on demand | secret-scan of one file before its text is posted |
| `diff-coverage.sh` | CI (opt-in) | changed-line coverage against a threshold |
| `gitleaks-fetch.sh` | called by the below | downloads + verifies the pinned scanner |
| `gitleaks-bin.sh` | called by the layers | the one place that decides which gitleaks runs |
| `base-ref.sh` | called by the layers | the one place that decides what "this change" is |

Copy the directory as a whole — the scripts call each other.

## Local layer
```bash
pip install pre-commit && pre-commit install   # installs BOTH hook types (pre-commit + pre-push)
bash ci/gate.sh --staged      # run the full gate on staged changes
bash ci/gate.sh --selftest    # prove it can fail (see below)
```
`gate.sh` uses a `gitleaks` on PATH, else fetches a pinned, checksum-verified
binary via `ci/gitleaks-fetch.sh` (no docker needed).

**Prove the gate can fail before trusting its green.** A gate nobody has seen
fail is not known to be wired up: a mis-set `MIGRATION_DIRS`, an allowlist
that swallows everything and a scanner that never started all read exactly
like a clean diff. `ci/gate.sh --selftest` stages known-bad and known-good
fixtures in a throwaway repo and judges them with *this* repo's scripts,
scanner and `.gitleaks.toml`: an unmarked `DROP TABLE` (must fail), a marker
without a reason (must fail), a marked drop (must pass), an edit to a
committed migration (must fail), a broken `awk` (must fail closed), a
credential-shaped line (gitleaks must trip), a bidi override (unicode-guard
must trip) and ZWJ-emoji prose (must pass). The fixtures land under the first
of your `MIGRATION_DIRS`, and it warns when none of those dirs exists in the
repo. It proves wiring, not coverage — one known-bad input per rule reaches
the failure path; it says nothing about violations it does not list.

**Pre-push layer.** `ci/pre-push.sh` scans the commits about to leave the
machine, per ref, before the remote has them — the cases the commit hook never
saw: `git commit --no-verify`, an amend, a rebase, history made elsewhere. Range
per ref: `remote..local` when the remote sha is known here; otherwise
`merge-base(default branch)..local`; otherwise the whole history of the ref —
more, never less. A git failure while computing the range **blocks** the push.
Bypass only with `GATE_PREPUSH_SKIP="<reason>"`, which appends
`time user refs reason` to `.git/gate-bypass.log` (local, readable in a
post-mortem). Installed through pre-commit it scans the first ref of a push
(pre-commit's contract); `cp ci/pre-push.sh .git/hooks/pre-push` covers every
ref. `git push --no-verify` skips it — the CI secret-scan is the backstop.

**Scan-at-sink.** `ci/scan-text.sh <file>` runs the same scanner, same rules,
on one file — a merge-request description, a tracker close comment, a release
note, a pasted log — *before* the text is posted. Write the text to a file,
scan it, post that same file: the bytes scanned are the bytes that leave.
Path allowlists in `.gitleaks.toml` apply to the file's name, so call it
`comment.md`, never `*.example`.

## CI variant (GitLab)
Two include files ship — pick by your runner **executor**:
- **docker / kubernetes** executor → `ci/ci-gate.gitlab-ci.yml` (uses `image:`).
- **shell** executor → `ci/ci-gate.shell.gitlab-ci.yml`. On a shell runner
  `image:` is ignored, so the docker variant won't run. The shell variant fetches
  a pinned gitleaks in-job (no docker, no runner change) and needs a project
  CI/CD variable `GATE_RUNNER_TAG` = your shell runner's tag.

Secret-scan is **incremental**: MR → the MR's commits; default-branch push → only
new commits; scheduled pipeline → full-history audit. Set up a pipeline schedule
so the periodic full scan runs.

## Pinned gitleaks
One scanner version, pinned in every path it runs through — so the local hook,
the shell runner and the docker/GitHub jobs give the same verdict on the same diff:

| Path | Pin | Where |
|---|---|---|
| shell runner / local `gate.sh` | version + **committed** SHA256 of the tarball (trust anchor) | `ci/gitleaks-fetch.sh` |
| GitLab docker/k8s, GitHub Actions | image **digest** (`ghcr.io/gitleaks/gitleaks:vX@sha256:…`) | `ci/ci-gate.gitlab-ci.yml`, `.github/workflows/gate.yml` |
| pre-commit | **commit** SHA of the release tag (`rev: <sha>  # vX`) | `.pre-commit-config.yaml` |

`gitleaks-fetch.sh` takes a **private copy** of the cached tarball, verifies
that copy against the committed SHA256 on **every** call, and extracts that
copy — nothing read from the shared runner cache runs without passing the
committed sum first (isolation between concurrent jobs of the *same* runner
user is the runner's property, not the script's). A tag or a `:latest` is
re-pointable upstream; a digest, a commit and a checksum are not. The extracted
binary lives in a per-call dir under `GITLEAKS_RUN_DIR` (default `$TMPDIR`);
the caller removes it — `gate.sh` does, and the shell CI variant points it at
the job workspace and cleans it in `after_script`.

Local `gate.sh` uses a `gitleaks` already on `PATH` if there is one (yours,
whatever version — an old one silently ignores the `[[allowlists]]` syntax of
`.gitleaks.toml`, which errs on the strict side); `GATE_PINNED_ONLY=1` makes it
fetch the pinned one instead, for the same verdict CI will give.

A frozen scanner goes stale — bump all four together: `PIN_VERSION` + both
SHA256s (from the release `checksums.txt`, checked once by a human), the image
digest (`docker buildx imagetools inspect ghcr.io/gitleaks/gitleaks:vX`), and the
pre-commit `rev`. Never `pre-commit autoupdate` this repo.

## migration-guard policy
On any changed file under a migrations dir:
- an **already-committed** migration modified / deleted / renamed → **FAIL** (forward-only);
- a **new** migration with a destructive statement in its **forward part** →
  **FAIL** unless the same file carries a marker comment **with a reason**:
  `-- destructive: approved (<ticket or reason>)`. A bare
  `-- destructive: approved`, `approved ()` or `approved (  )` is not an
  approval — the parenthesised reason is what a reviewer and a post-mortem
  hold someone to; who may approve is CODEOWNERS' job (below), not the
  marker's. Two pattern families: SQL, case-insensitive —
  `DROP <table | column | schema | database | index | constraint | view | type |
  sequence | trigger | function | procedure | materialized view>`, `TRUNCATE`,
  `DELETE FROM`, `ALTER TABLE … DROP <anything>` (the `COLUMN` keyword is
  optional in PostgreSQL/MySQL); and the DSL tokens of the frameworks whose dirs
  are scanned by default, case-sensitive, whole words — Rails/Alembic
  `drop_table`/`drop_column`/`remove_column(s)`/`remove_reference`/
  `remove_belongs_to`/`remove_timestamps`/`drop_join_table`, Django
  `DeleteModel`/`RemoveField`, Laravel `Schema::drop`/`Schema::dropIfExists`/
  `dropTimestamps`/`dropSoftDeletes`, Knex/Sequelize/TypeORM
  `dropTable(IfExists)`/`dropColumn(s)`/`removeColumn`. "Forward part" =
  everything except the **body of the `down` / `downgrade` block** that follows
  an `up` / `upgrade` / `change` definition at the same indentation: a
  conventional `down()` drops exactly what `up()` created — in DSL or in SQL
  (`queryRunner.query("DROP TABLE …")`, `op.execute("DROP …")`) — and flagging
  every reversible migration would make the marker worthless. The body is
  recognised by indentation (deeper lines, a lone `{`, the closing `end`/`}`),
  so helpers after the block, a redefined `up`, and anything else in the file
  are scanned. A `down:` key or a `down(q)` call nested inside `up()` is not a
  definition, and a one-line Rails `dir.down { … }` inside `reversible` is not
  scanned as a whole line. Files without an `up` definition (plain `.sql`
  incl. `-- +goose Down`-style sections, `*.down.sql`, Django, down-only
  files) are scanned in full. Layouts that still need the marker when their
  `down` drops something (fail-strict, not a bug): a multi-line
  `dir.down do … end`, `reversible do |direction|`, a one-line
  `def down; drop_table :t; end`, tabs in `up` vs spaces in `down`, and SQL
  or a comment at column 0 inside the `down` body (a `<<-SQL` heredoc, a
  template literal) — a dedented line ends the block. The verdict
  fails closed (`exit 2`) when `awk`/`grep` themselves fail — a missing tool is
  not a clean migration.

Env: `MIGRATION_DIRS` (default `migrations db/migrate db/migration prisma/migrations`),
`GATE_BASE_REF` (override the diff base), `STAGED=1` (check the index).
Exit codes: `0` ok · `1` policy violation · `2` config/infra (fails closed).

Deliberate destructive change is fine — mark it, with the reason:
```sql
-- destructive: approved (TICKET-123: data archived to s3://…, restore tested)
DROP TABLE legacy_sessions;
```

**Known limits / bypasses** — migration-guard (so nobody mistakes the guard's
perimeter for coverage): the match is per line, so a statement split across lines
(`DROP\nTABLE`), SQL assembled from several strings, `DELETE` without `FROM`
(MSSQL), a type change that truncates data (`ALTER COLUMN … TYPE`),
`RunSQL`/`RunPython` with non-literal SQL, constraint-dropping DSL calls
(`dropForeign`, `remove_index`), a migration DSL not listed above, and
data-destroying `UPDATE`s are **not** detected. The forward-part rule is a
convenience for conventional layouts, not a security boundary: a destructive
statement deliberately indented into a `down` block, or hidden behind an
`up: realUp` alias, passes. That residue is the LLM security review's job (it
reads the migration, not a regex); widening this regex into a parser is not.
Nor does the guard re-read migrations that are already committed — it judges
what an MR adds. And the guard lives in the repository it judges: the
`CODEOWNERS` file shipped next to it puts `ci/`, `.gitleaks.toml`,
`.pre-commit-config.yaml` and the CI files under the gate owner's required
review, so the party under check cannot narrow a regex in the same MR — see
Protected-branch below for making that review *required*.

## unicode-guard policy
Added lines of the diff must not carry code points a reviewer cannot see
but a compiler or an LLM reads: bidi overrides/isolates (`U+202A–202E`,
`U+2066–2069`), zero-width space / word joiner (`U+200B`, `U+2060`),
`U+FEFF` anywhere but as a file's leading BOM, and the Unicode tag block
(`U+E0000–E007F`, ASCII smuggling). Deliberately **not** flagged: ZWJ/ZWNJ
(emoji sequences, Arabic and Persian typography), LRM/RLM, soft hyphen —
ordinary non-ASCII prose must never trip it, or it gets switched off. Known
false positive: subdivision flag emoji (🏴 + a tag sequence). Files git treats
as binary are not diffed as text and are reported as skipped. Matching is
done by `awk` under `LC_ALL=C` on purpose: GNU grep in the C locale silently
fails to match byte ranges ≥ 0x80, which would read as a clean verdict.

Env: `UNICODE_GUARD_EXCLUDE` (ERE over paths — vendored fonts, i18n fixtures;
empty = everything), `GATE_BASE_REF`, `STAGED=1`.
Exit codes: `0` ok · `1` forbidden code point · `2` config/infra (fails closed).

## When secret-scan fires
The order matters; under stress people do it backwards.
1. **Revoke or rotate the credential at the provider — first**, before
   touching git. Forks, clones, CI logs and caches already hold the history;
   a scrubbed history with a live key is a live key.
2. **Size the exposure window:** when it was committed (`git log -S'<prefix>'
   --all --format='%h %ad %an'`), whether the repo was public, mirrored or
   forked in that window, whether the value reached CI logs or artifacts.
3. **Not yet on a shared branch** (pre-push or MR pipeline caught it): remove
   it from the branch — `commit --amend` / interactive rebase — and force-push
   *your* branch. The default branch is untouched.
4. **Already on a shared branch:** scrub history (`git filter-repo
   --replace-text`, or BFG). That is a force-push, which this gate's
   protected-branch rule forbids — lift the protection **deliberately, for
   the duration, on the record** (who, when, why), re-apply it, and have every
   clone re-fetch. Do not skip step 1 because of this step.
5. **Audit:** provider access logs for the window; if gitleaks missed a
   variant, add a *rule* to `.gitleaks.toml`, never an allowlist entry.
6. Never allowlist "because it is rotated now" — the next one will not be.

## Upgrading the payload
The marker at the top of this file says which payload version is vendored here.
Re-running the `ci-gate` skill upgrades it: the `ci/` scripts and this README are
replaced, while `.gitleaks.toml`, `.pre-commit-config.yaml`, `CODEOWNERS` and the
CI files are *merged* — your `MIGRATION_DIRS`, coverage wiring and extra rules
survive. After an upgrade, two things are not automatic:
- **required status checks** — a new gate job (1.8.0 added `unicode-guard`) is
  only enforced once it is in the branch-protection contexts; until then it is
  a check that can go red without blocking anything;
- **the reason-bearing marker** (1.8.0) — before merging the upgrade, find the
  markers that will start failing:
  `git grep -nE 'destructive:[[:space:]]*approved([^(]|$)' -- <your migrations dirs>`.
  A migration that is already committed cannot be edited (forward-only), so fix
  those on the integration branch with the gate owner, or add the reason in the
  same MR that brings the upgrade.

## diff-coverage policy

Global coverage % is vanity — it moves too slowly to notice an untested change.
This layer looks only at the lines the MR added or modified.

`ci/diff-coverage.sh` **judges** a coverage report, it never produces one: your
test job writes lcov / Cobertura / Clover, this reads it.

Env: `GATE_COVERAGE_REPORT` (path(s); unset → layer skips itself),
`GATE_COVERAGE_MIN` (default `80`), `GATE_COVERAGE_STRICT=1` (a change with
nothing measurable fails instead of passing — turn on once the report path is
proven), `GATE_BASE_REF`, `GATE_COVERAGE_MISSES`.
Exit codes: `0` ok · `1` below threshold · `2` config/infra (fails closed).

Coverage is a detector, not a target: a test that touches lines without
asserting anything satisfies this gate and proves nothing. Mutation testing is
what catches that — run it on the changed files, not the whole repo.

## Protected-branch (one-time, per repo)
Force-push cannot be checked by a CI job — set it as a platform rule.

**GitLab:**
```bash
PROJ="group/repo"; BR="main"; ID=$(printf %s "$PROJ" | jq -sRr @uri)
glab api -X PUT "projects/$ID" -f only_allow_merge_if_pipeline_succeeds=true \
  -f only_allow_merge_if_all_discussions_are_resolved=true
glab api -X DELETE "projects/$ID/protected_branches/$BR" 2>/dev/null || true
glab api -X POST  "projects/$ID/protected_branches?name=$BR&allow_force_push=false"
```

**GitHub** (`contexts` must match the workflow job names; the review block
makes the `CODEOWNERS` approval on gate files *required* — count `0` means
only MRs touching owned files need a review, the rest merge on green):
```bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{ "required_status_checks": { "strict": true, "contexts": ["secret-scan","migration-guard","unicode-guard"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "require_code_owner_reviews": true, "required_approving_review_count": 0, "dismiss_stale_reviews": true },
  "restrictions": null }
JSON
```

**Gate files under required review (`CODEOWNERS`).** The scripts, the
scanner rules, the hook config and the CI job definitions decide the verdict;
the MR under check must not be able to edit them without the gate owner's
approval. The shipped `CODEOWNERS` lists them — replace `@OWNER`, then make the
review required: GitHub — the `required_pull_request_reviews` block above;
GitLab — `glab api -X POST "projects/$ID/protected_branches?name=$BR&code_owner_approval_required=true"`
(**Premium**; on Free tier the file assigns reviewers and enforces nothing —
write that down rather than assume it). Solo repo: an author cannot approve
their own MR, so either a second account owns the gate or you keep the file
for visibility and skip enforcement, knowingly. Control it like the rest:
open an MR that narrows `SQL_RE` and confirm it asks for the owner's review.

## Known limits — the whole gate
Every layer here is a floor with a documented residue. The residue is the LLM
review's job (it reads the change; a scanner reads bytes), never a reason to
grow a regex into a parser:
- **`# gitleaks:allow`** on a line suppresses the secret-scan in every path —
  pre-commit, pre-push and CI. It is the cheapest bypass there is, and it is
  deliberate: a one-off example in docs should not need a global allowlist.
  A **new** `gitleaks:allow` (or `unicode-guard:allow`, or a widened
  `[[allowlists]]`) in a change is a review finding, not a detail.
- **`.gitattributes`** decides what git shows as text. The CI scans and
  `pre-push.sh` pass `--text`, so a `-diff` attribute cannot hide a file from
  them; the local `pre-commit` hook and `gate.sh --staged` run
  `gitleaks protect --staged`, which has no such override — a file marked
  `-diff` is invisible there until CI sees it. Own `.gitattributes` in
  `CODEOWNERS` (the shipped file does).
- **Merge commits**: `git log -p` shows no patch for a merge, so a secret
  introduced *in* a conflict resolution is invisible without
  `--diff-merges=first-parent`. Every range scan here passes it; a scan you add
  yourself must too.
- **`--log-opts` is space-split by gitleaks**: an empty word in it makes the
  scan cover nothing and still exit 0. Build it as the templates do.
- **A broken git range exits 0** inside gitleaks ("0 commits scanned, no leaks
  found"), which is why the templates validate the range with `git rev-list`
  before scanning.
- **Homoglyphs / mixed-script identifiers** (`раssword` with a Cyrillic `а`)
  are not detected by unicode-guard — the bytes are ordinary letters. That is
  the security review's job.
- **`pre-push.sh` is advisory**: `git push --no-verify`, a `core.hooksPath`
  that points elsewhere, or a client without hook support all skip it, and
  `.git/gate-bypass.log` only records the honest bypasses. The CI secret-scan
  is the enforced floor.
- **The destructive marker is a declaration, not an approval.** Anyone who can
  write the migration can write `-- destructive: approved (T-1)`. What makes it
  an approval is a reviewer — put your migrations dirs in `CODEOWNERS` if you
  want a second signature.

Scaffolded by the `task-flow` Claude Code plugin (`ci-gate` skill).
