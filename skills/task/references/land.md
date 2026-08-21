# Landing: verify → merge → deploy → verified (phases 7–8)

Loaded in **phase 7**, and it carries phase 8 as well — verification before the
merge (phase 7) and everything after it are one landing sequence, and §6's
cleanup rules are needed at the end of phase 7. Everything here is about the stretch nobody writes down —
between "the MR is approved" and "the change is actually running". The failure
classes below are all recoverable **if** you know the state; each one becomes
unrecoverable the moment you act on a guess.

The commands are per-platform pairs; use the project's VCS binding. When
neither CLI is installed, the git-native fallback is named — a missing tool is
never a reason to skip the check.

## 1. Merge

Before merging:
- **The MR body describes what the range does.** Compare it with
  `git log --oneline <base>..HEAD`: functionality in the range that the body
  never mentions (or a body describing something no longer there) is a
  finding — fix the body, do not merge past it.
- **Green means the gate jobs ran and passed** (phase 8 rule). Name them.
- **The final fresh run happened on the merged state**, not on your branch
  alone: merge/rebase the integration branch in first (per the project's
  CLAUDE.md). A conflict resolution is a new edit — it goes back through a
  delta review before it lands.

Merging:
```bash
gh pr merge <id> --squash|--merge|--rebase        # method from the project binding
glab mr merge <id> --squash|--merge|--rebase
```

**If the merge command exits non-zero, do not run it again.** A server-side
merge that succeeded while the local cleanup failed is a known class, and a
second merge on a re-created branch is how you get a duplicated history or a
revert of someone else's work. Ask the platform what is true:
```bash
gh pr view <id> --json state,mergedAt,mergeCommit,mergeStateStatus
glab mr view <id> --output json | jq '{state, merged_at, merge_commit_sha, detailed_merge_status}'
# no CLI: git fetch origin <base> && git branch --contains <head-sha> -r
```
- merged → continue with the reported merge commit;
- open + a failing/blocked state → that state is the finding (CI red, conflicts,
  missing approval, permission denied): report and stop;
- unknown → stop. Never re-merge to find out.

**Merge queue / auto-merge** (`gh pr merge --auto`, GitLab merge trains): the MR
is not merged when the command returns. Poll state with a timeout you name, and
report progress; if the MR falls out of the queue (state back to open, or the
train restarts without it), STOP — that is a new CI failure to read, not a
retry to fire.

## 2. Deploy

- **Look for the pipeline that already deploys.** A CI run whose head sha is the
  **merge commit** and whose name matches deploy/release/cd means the deploy is
  someone else's job:
  ```bash
  gh run list --commit <merge-sha> --json name,status,conclusion,databaseId
  glab ci list --sha <merge-sha>
  ```
  Found → wait for it (report its conclusion), never deploy a second time in
  parallel. Not found → deploy with the project's command from the binding.
- **Deploying by hand** is an outward-facing action: confirm unless the project
  durably authorised it, and never invent the command — it comes from the
  Deploy binding, or you stop and say the binding is missing.

## 3. How deep to verify

Depth follows the scope of the diff — say which level you used. The same table
applies twice: in phase 7 against the dev/staging environment before the merge,
and after the deploy against the environment the change actually landed in.

| Scope of the change | What "verified" means here |
|---|---|
| docs / comments only | nothing to verify; say so |
| config / CI | the target loaded the new config (health endpoint, job log, `2xx` on one route) |
| backend | the touched endpoint answers as the DoD says; error log for the deploy window is clean of new entries |
| frontend | the user path from phase 7, re-run against the deployed URL |
| migration / data | the migration ran (tool status), and the data invariant it protects is checked once, by query |

## 4. Landing state

The **first line** of the close comment is the task's terminal status
(`DONE | DONE_WITH_CONCERNS | BLOCKED | MERGED_NOT_LIVE | ABANDONED`, derived
from the table in `implementation-integrity.md` §6). What happened to the change
itself is a separate field on its own line, so the two vocabularies never share
a token:

```
landing: deployed | deployed-with-concerns | not-live | reverted
```

| `landing:` | When |
|---|---|
| `deployed` | merged, deployed, verified at the depth above |
| `deployed-with-concerns` | live, but something named is unresolved (flaky check, follow-up ticket, partial DoD) |
| `not-live` | merged, not running — deploy failed, was not triggered, or verification failed |
| `reverted` | landed and taken back out; say why, and link the revert MR |

**`not-live` is a state, not an accident.** In this order:
1. read the deploy logs and say what failed;
2. if the change is live-broken rather than merely absent, take it out — and
   **a revert is a change like any other**: branch, `git revert -m 1
   <merge-sha>`, MR, gate green, merge. Never push a revert straight to a
   protected branch: that is the one moment when a force-push or a bypass looks
   justified, and it is exactly when the gate matters most. If the platform
   refuses the merge, that refusal is the finding — report it, do not
   improvise;
3. re-run the health check afterwards and update the field.

## 5. Posting the close comment

The comment is the task's public record, so it is also the last place a secret
can leave: **scan it at the sink**. Write the comment (and the MR description)
to a file, run `bash ci/scan-text.sh <file>` when the repo carries the gate, and
post *that same file* — a pasted log or config snippet is how a credential
reaches a tracker, where no hook runs. `rc 1` → do not post it; rotate the
credential first. `rc 2` → the scanner could not run, which is not a clean
verdict: fix it, or say in the evidence block that the text went out unscanned.
No `ci/scan-text.sh` in the repo means the gate predates it — note that rather
than skip silently.

Shape (the rules behind each part are in `implementation-integrity.md` §6):

```
DONE_WITH_CONCERNS — merged and live; DoD-4 accepted by <risk owner> on the MR
landing: deployed

Что сделано: <per surface>
DoD-1 → PASS (src/api/orders.py:88) · DoD-2 → PASS (`make check`, вывод ниже)
DoD-3 → UNVERIFIABLE (DNS у платформенной команды, тикет OPS-77, проверит <кто>)
DoD-4 → PARTIAL (принято <risk owner> на MR, follow-up DEV-512)

тесты 47/47 · diff-coverage 31/31 (100%) · мутанты 5/5 killed ·
CI green (secret-scan, migration-guard, unicode-guard, diff-coverage) ·
review @ 3f2a1c9 · re-reviewed: n/a (merge only) · security @ skip (нет
чувствительных поверхностей) · HEAD @ 9c1b7d2 · node: pin 20.11.1 · actual
20.11.1 (match) · live на dev: <url> · repro: `make check` · property-тесты:
пропущены, в изменении нет инвариантов

MR: <url> · follow-ups: DEV-512
```

## 6. Always stop / never stop

**Always stop and report** (never retry, never work around): CI red on the merge
commit, merge conflicts, permission denied, MR not found, deploy failure, a
migration that failed halfway, the MR falling out of a merge queue.

**Never stop for** (decide and note it): which merge method the binding names,
a poll timeout you can extend once with a reason, a formatting-only difference
in the MR body, a deploy log line that predates this deploy window.

## 7. Cleanup

Delete only what this session created: a fixture directory, a review worktree,
a temp file whose path you wrote down when you created it. The task's own
`<TASK-ID>.state.md` is this flow's artifact, not a path from outside: delete it
when the task closes (the spec stays). Before removing a
path: resolve it (`realpath`), check it is inside the workspace you created,
check there is no `.git` inside it, and check the path did not come from
outside (an argument, a checkpoint file, a ticket). Any of those failing means
you do not delete — you report the leftover. Delete by the resolved path, never
by the string you were handed.
