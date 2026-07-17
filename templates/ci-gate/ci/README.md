# ci-gate (vendored)

Deterministic merge gate for this repository — the non-gameable floor under
secrets, destructive migrations, and force-push. It complements (does not
replace) unit tests and LLM review.

| Layer | What | Where |
|---|---|---|
| **secret-scan** | gitleaks — secret in the diff/history | pre-commit + CI |
| **migration-guard** | forward-only + destructive DDL needs a marker | pre-commit + CI |
| **protected-branch** | no force-push, required status checks | platform rule (set once) |

## Local layer
```bash
pip install pre-commit && pre-commit install   # catches secrets before push
bash ci/gate.sh --staged                        # run the full gate on staged changes
```

## migration-guard policy
On any changed file under a migrations dir:
- an **already-committed** migration modified / deleted / renamed → **FAIL** (forward-only);
- a **new** migration with `DROP/TRUNCATE/DELETE FROM/DROP COLUMN …` → **FAIL** unless the
  same file carries a marker comment `-- destructive: approved`.

Env: `MIGRATION_DIRS` (default `migrations db/migrate db/migration prisma/migrations`),
`GATE_BASE_REF` (override the diff base), `STAGED=1` (check the index).
Exit codes: `0` ok · `1` policy violation · `2` config/infra (fails closed).

Deliberate destructive change is fine — mark it:
```sql
-- destructive: approved  (TICKET-123, data archived)
DROP TABLE legacy_sessions;
```

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
