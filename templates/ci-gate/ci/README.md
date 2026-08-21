# ci-gate (vendored)

Deterministic merge gate for this repository — the non-gameable floor under
secrets, destructive migrations, and force-push. It complements (does not
replace) unit tests and LLM review.

| Layer | What | Where |
|---|---|---|
| **secret-scan** | gitleaks — secret in the diff/history | pre-commit + CI |
| **migration-guard** | forward-only + destructive DDL needs a marker | pre-commit + CI |
| **diff-coverage** | changed lines actually executed by a test, above a threshold | CI (opt-in) |
| **protected-branch** | no force-push, required status checks | platform rule (set once) |

## Local layer
```bash
pip install pre-commit && pre-commit install   # catches secrets before push
bash ci/gate.sh --staged                        # run the full gate on staged changes
```
`gate.sh` uses a `gitleaks` on PATH, else fetches a pinned, checksum-verified
binary via `ci/gitleaks-fetch.sh` (no docker needed).

Run it once against a deliberately bad change — an unmarked `DROP TABLE` in a
new migration under a configured migrations dir — and watch it go red before
you trust a green. A gate nobody has seen fail is not known to be wired up:
a mis-set `MIGRATION_DIRS` looks exactly like a clean diff.

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
  **FAIL** unless the same file carries a marker comment
  `-- destructive: approved`. Two pattern families: SQL, case-insensitive —
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
  `def down; drop_table :t; end`, tabs in `up` vs spaces in `down`. The verdict
  fails closed (`exit 2`) when `awk`/`grep` themselves fail — a missing tool is
  not a clean migration.

Env: `MIGRATION_DIRS` (default `migrations db/migrate db/migration prisma/migrations`),
`GATE_BASE_REF` (override the diff base), `STAGED=1` (check the index).
Exit codes: `0` ok · `1` policy violation · `2` config/infra (fails closed).

Deliberate destructive change is fine — mark it:
```sql
-- destructive: approved  (TICKET-123, data archived)
DROP TABLE legacy_sessions;
```

**Known limits / bypasses** (so nobody mistakes the guard's perimeter for
coverage): the match is per line, so a statement split across lines
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
what an MR adds. And the guard lives in the repository it judges: without
required review on `ci/`, `.gitleaks.toml` and the CI files (CODEOWNERS), the
party under check can edit it in the same MR — that protection is the next
layer, not this script.

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

**GitHub** (`contexts` must match the workflow job names):
```bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{ "required_status_checks": { "strict": true, "contexts": ["secret-scan","migration-guard"] },
  "enforce_admins": true, "required_pull_request_reviews": null, "restrictions": null }
JSON
```

Scaffolded by the `task-flow` Claude Code plugin (`ci-gate` skill).
