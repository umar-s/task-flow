---
name: task
description: >-
  Execute ONE tracked task/ticket end-to-end through a disciplined per-task
  quality flow — ingest + design-spec, two premortems, TDD implementation,
  adversarial code-review, conditional security-review, live verification, then
  close the ticket with a "что сделано" summary, Done, and Spent time.
  Use whenever the user invokes
  /task, or asks to implement/do a ticketed task (DEV-XXX, JIRA-XXX, #123,
  "сделай задачу …", "прогони через наш flow / loop-пайплайн") with rigor.
  One task = one feature branch → MR, CI green before merge.
---

# Per-task quality flow

A single, supervised pass that takes one tracked task from ticket to closed,
with quality gates the user relies on. The **discipline below is fixed**; the
**concrete commands are project-specific** — read the project's `CLAUDE.md`
first and map each "run the project's …" step to the real command there.

**Argument:** the task id (e.g. `DEV-475`). If none was given, ask which task.

**Setup:** create one todo per phase (0–8) so progress is visible, and mark
each done as you go. Do the phases in order — do not skip a premortem because
the task "looks simple"; that is exactly when gaps hide.

## Project bindings — resolve these from CLAUDE.md before starting
- **Tracker** — how to read a ticket + its comments, post a comment, set state
  Done, log Spent time, assign, and link related tickets (API + token).
- **VCS/CI** — integration branch to base work on (e.g. `develop`), how to open
  an MR/PR, and how to check the pipeline status.
- **Build/verify** — test, static-analysis, and lint commands; how to deploy to
  the dev/staging environment; whether a browser-verify surface exists and its URL.

## Reference loading (resolve once, read lazily per phase)

Phases 5, 6 and 6b each load one reference file under this skill's
`references/` dir. Resolve the base path **once**, at the start, with a bash
step:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "<this SKILL.md's own path>")/../.." && pwd)}"
echo "$ROOT"
```

`CLAUDE_PLUGIN_ROOT` is set when this runs as an installed plugin; the
fallback walks up from this file's own location when it doesn't. Either way
`$ROOT` is an **absolute path on disk**, and every reference load for the
rest of the session is:

```
Read "$ROOT/skills/task/references/<file>.md"
```

using the **resolved value of `$ROOT`**, substituted in before the Read
call — never pass the literal string `${CLAUDE_PLUGIN_ROOT}` to the Read
tool; it does not expand shell/env syntax, so a literal pass reads nothing.
Load lazily, one phase at a time: phase 5 needs only
`implementation-integrity.md`, phase 6 only `code-review-prompt.md`, 6b only
`security-review-prompt.md`. **A Read that fails stops the phase.** Never
continue from memory of what the reference "probably says" — a reference that
did not load is exactly how a phase degrades into plausible invention that
reads like a pass.

## 0. Ingest
Read the ticket **and every comment** in the tracker — the real DoD and the
"важное уточнение" often live in a late comment, not the title. Assign the task
to the user if it is not already. Restate the DoD and constraints back in one
short paragraph so scope is explicit. If scope genuinely forks, ask **now**
(AskUserQuestion) — not after implementing. Ask from the **frontier**: the
decision whose prerequisites are already closed and that unblocks the most of
what follows; questions that depend on its answer wait for it. Two options with
the same consequences are not a decision — pick one, state it as an assumption,
move on.

**Declare the tier** in that restatement, one line. It scales the *artifacts*,
never the gates:
- **T1 trivial** — copy, config value, comment, one surface; no data, auth,
  migration or external call. Phase 1 is three sentences in the ticket; phases
  2 and 4 may legitimately conclude "no failure mode beyond X" in a line each.
- **T2 normal** — a bug fix or a contained feature. The flow as written.
- **T3 high-stakes** — money, auth/permissions, data loss, concurrency,
  migrations, public API. Phase 2 starts from an explicit failure model, the
  phase-5 mutation check is mandatory, and 6b is not optional.

**A phase that finds nothing says so.** Never invent a risk to justify having
run a premortem, and never harden beyond the DoD without a named requirement.
Manufactured risk becomes manufactured scope: on a small ticket that is the
likeliest way this flow damages the change instead of protecting it — an
imagined failure mode in phase 2 turns into an invented requirement in the
spec, which phase 6 then dutifully enforces. Phases 6b, 7 and 8 never scale
down with the tier.

## 1. Design-spec
Write a short design doc: data model / schema, endpoints or interfaces, the
behavioural contract, and any scope forks. Cross-check every DoD field against
what the code will actually parse/expose (spec→implementation coverage). Save it
where the project keeps design artifacts (e.g. `loops/specs/` or `docs/`).

## 2. Premortem #1 — on the design
Adversarially assume the design shipped and caused a problem. Enumerate concrete
failure modes: missing fields, wrong states, cache/permission/transaction gaps,
concurrency, back-compat. Fix the design for each real risk before planning.

**Escalation — full `premortem` session (conditional).** If the `premortem`
skill is installed (check the available skills list) AND the task is
high-risk — destructive or data-bearing migrations, auth/permission changes,
payment paths, external integrations, irreversible operations — or the user
asks for it, **offer** to run that skill on the design-spec instead of the
inline pass above. It is an interactive session (parallel helpers, per-hole
decisions, ~10–15 min of the user's time), so it is offered, never forced;
declined or absent → the inline pass above is the gate, as before. When it
runs, its artifact `docs/premortem/<slug>.md` feeds the rest of the flow:
accepted holes → design fixes now; their edge cases → the phase-5 tests and
the `[PREMORTEM_EDGES]` slot of the phase-6 review dispatch (deliberately not
6b: the security pass walks the trust boundaries itself instead of inheriting
the team's worry-list). Phase 4's plan premortem stays inline regardless — it
attacks execution mechanics, not the design.

## 3. Execution plan
Turn the corrected design into ordered, concrete steps: files to touch, tests to
write, migrations, grants, docs, deploy + cache-flush steps.

Before fixing the order, map **blast radius and risk**: the contracts and data
other consumers depend on, the callers and flows the change touches, and the
unknown that costs the most if it turns out wrong. Then order so that the
riskiest assumption is proven **earliest**. An unknown that cannot be proven
inside the first slice becomes a bounded spike step with a named exit decision —
not a hope deferred to the end.

Choose the **test seam** here, not while writing tests: the highest practical
level that still proves user-observable behaviour, preferring an existing seam
over a new one and a real boundary (route, DB, queue) over a deep mock. A
mock-shaped seam that stays green while the real path is broken is exactly the
failure this step prevents. Record the chosen seam in the plan; escalate the
choice to the user only when it changes a contract, the cost of the work, or how
much the result can be trusted.

## 4. Premortem #2 — on the plan
Attack the plan the same way: wrong ordering, a mutation that commits before a
guard, a missing grant/migration, an un-flushed cache, an untested edge. Fix.

## 5. TDD implement
Load `implementation-integrity.md`
(`Read "$ROOT/skills/task/references/implementation-integrity.md"`)
before the first test: baseline on a repo that isn't already green, RED means
you *watched* it fail, the anti-gaming rules, the mutation check that proves the
tests would notice a wrong answer, and the "numbers, not adjectives" rule that
phases 7–8 report against.

Branch off the integration branch (`fix/…` or `feature/…`, one branch per task).
Implement to the DoD. Write tests **at the seam chosen in phase 3** that encode
the DoD and the premortem edge cases. Run the project's **test +
static-analysis + lint** to green. Keep spec-adjacent docs (API reference,
OpenAPI) in the same change.

## 6. Code-review (adversarial)
Run an independent, adversarial review of the diff — the `code-review` Workflow
at high effort, or a **fresh reviewer subagent** dispatched with
`code-review-prompt.md`
(`Read "$ROOT/skills/task/references/code-review-prompt.md"`).
Independence is structural, not aspirational: the reviewer receives the flow's
artifacts — diff range (`git merge-base HEAD <integration-branch>` → `HEAD`),
DoD, design-spec, premortem edge lists — and **never the session transcript,
the implementation story, or the author's framing of what is "fine"**. A
reviewer briefed on the author's doubts inherits the author's blind spots: it
checks the five things you already worry about and skips the sixth you missed.
The review is read-only on the checkout (rules in the template). Treat findings
as suspects: fix the **real** correctness/security/grant/transaction ones and
add a test that would have caught each; dismiss noise with a one-line reason.
If `superpowers:receiving-code-review` is installed, process the findings
through it — it is the disciplined version of "treat findings as suspects", and
it is what keeps agreement from becoming performative.

**Severity maps to action.** Critical and Required block the merge. A Required
finding may also be closed by the risk owner *explicitly accepting* it with the
reason recorded on the MR — never by quietly downgrading it. Optional/Nit never
become mandatory work: batch them or drop them, don't let a nit list grow the
task. Fixes to Critical/Required findings go back through a fresh review of the
delta (same clean dispatch) until none remain — a fix is a new change, not an
epilogue.

**Grade findings, or the loop never terminates.** A *behavioural* finding — the
code does the wrong thing, a test cannot fail, a guard cannot fire — is fixed
and goes back through a fresh review of the delta. A *description* finding — the
spec, a comment or the MR text says something untrue about code that is
correct — is fixed and disclosed, and buys no new round. Without that split,
"fix everything, re-review after every change" has no fixpoint: prose always has
one more remark.

**A verdict attaches to the commit it saw.** Fixes made after the last review
mean the state you are about to merge was never reviewed — either re-review the
delta, or say so plainly in the phase-8 comment. Inheriting the previous verdict
silently is what turns the review into decoration.

## 6b. Security-review (conditional)
Run an **independent** security pass on the diff (`/security-review`, or a fresh
subagent dispatched with `security-review-prompt.md`
(`Read "$ROOT/skills/task/references/security-review-prompt.md"`) —
never the agent that implemented it, same clean-context rule as phase 6). A
distinct threat-model lens, not a correctness re-run: STRIDE walked from the
trust boundaries the diff touches — authz/permission bypass, injection
(SQL/command/template), SSRF, unsafe deserialization, secrets committed to
code, missing grants; on AI/agentic surfaces, prompt injection and the OWASP
LLM Top 10. It also owns the **capability diff** — did this change start using
the network, subprocesses, the filesystem, or credentials/env it did not touch
before? A capability nobody asked for is a finding even when it looks benign. **Critical/High findings require a PoC or a concrete exploitation
path** — can't produce one → downgrade; severity maps to action (Critical/High
block the merge, Medium → follow-up ticket, Low → backlog). A finding this pass
and the phase-6 review surface **independently** is a priority signal — never
collapse it as a duplicate.
**Gate by risk profile:** run it whenever the diff touches auth, external input,
network calls, secrets, data/PII, migrations, or grants; otherwise skip with a
one-line reason (as you would dismiss code-review noise). This is the *LLM*
layer — gameable and correlated with the implementer, so it does **not** replace
the deterministic CI gate in phase 8 (secrets / destructive DDL / deps), and
that gate does not replace this. Both, or neither means anything.

## 7. Verify live
Prove it on the actual dev/staging environment, not just in unit tests:
- **UI surface** (and frontend deployed) → drive it in a real browser
  (dev-browser / Playwright) through the user-visible path.
- **Backend-only** → hit the real endpoint (authed) or query the DB to confirm
  state; a feature/API test is the floor, not the ceiling.
Write assertions that check the *actual* value — beware helpers that mask it
(e.g. `x ?? default` turning a real `null` into the default and passing a wrong
check). Clean up any test fixtures you seeded.

## 8. Close
- Open the MR/PR; **verify the CI pipeline is GREEN before merging** — never
  blind-merge. "Green" must include the **deterministic gate** (secret-scan,
  migration-guard, dep/SCA), not only unit tests — that gate is what covers the
  blast-radius categories both the tests and the LLM security-review miss.
  Include means **present and passed**: list this pipeline's jobs (VCS/CI
  binding) and confirm the gate jobs actually ran on this MR. A pipeline that
  never scheduled them is green by omission — "not measured" is not "passed",
  and on GitLab "pipelines must succeed" is satisfied by a pipeline without
  them. Name the gate jobs in the evidence block, not just "CI green".
  Force-push protection is a platform rule (protected branch), not a pipeline
  job. Merge, deploy to dev, flush the caches the change touches.
  - Scaffold this deterministic gate into a repo once with the **`ci-gate`**
    skill (part of this plugin) — it drops `ci/`, the gitleaks + pre-commit
    config, the platform CI file, and prints the protected-branch commands.
- Post a **"что сделано"** comment to the tracker: what shipped (per surface),
  how it was verified (tests + live), the MR/PR links, and any follow-ups.
  The verification part is an **evidence block**, not an adjective: numbers
  from one final fresh run made after the last edit, the single command that
  reproduces them, and every skipped check named with its reason — e.g.
  "тесты 47/47 · diff-coverage 31/31 (100%) · мутанты 5/5 killed · CI green
  (secret-scan, migration-guard, unicode-guard, diff-coverage) · live на dev: <url> · repro:
  `make check` · property-тесты: пропущены, в изменении нет инвариантов".
  Never "всё зелёно" — a check nobody ran and nobody mentioned reads exactly
  like a check that passed. Shape and rules in
  `references/implementation-integrity.md` §6.
  **Scan outgoing text at the sink:** when the repo carries the gate, write
  the comment / MR description to a file, run `bash ci/scan-text.sh <file>`,
  and post that same file — a pasted log or config snippet is how a secret
  reaches the tracker, where no hook runs. rc 1 = do not post it (rotate the
  credential first); rc 2 = the scanner could not run, which is not a clean
  verdict — fix it, or say in the evidence block that the text went out
  unscanned. No `ci/scan-text.sh` in the repo means the gate predates it: note
  that instead of skipping silently.
- Set state **Done** and log **Spent time**.
- If the work spans surfaces (e.g. backend + frontend), create/link the paired
  ticket and note it.

## Fixed discipline (non-negotiable)
- Where this flow and the project's `CLAUDE.md` genuinely conflict, the project
  wins — apply its rule and say in one line which step you deviated from and
  why. A silently skipped step is the failure; a declared one is a decision.
- One task = one feature branch off the integration branch → one MR/PR.
- CI pipeline **green before merge**; if a prior merge was blind, that is the bug.
- Never commit `Co-Authored-By` trailers unless the project asks for them.
- Never hand-edit tracker/migration bookkeeping tables; use the proper commands.
- **Never `--no-verify` and never `GATE_PREPUSH_SKIP`.** A hook that blocks a
  commit or a push is a finding to fix, not friction to route around: rc 1 is a
  real secret (rotate it, then rewrite the commit), rc 2 is a broken clone or
  tool (fix that). Bypassing a gate is the user's call, with their reason on
  the record — never the agent's.
- Watch monorepo/symlink traps: stage the **real** file path, not a symlinked one.
- Report honestly: if a step was skipped or a test failed, say so with the output.
- Confirm outward-facing / irreversible actions (deploys, merges, external
  posts) unless the project has durably authorized them.
