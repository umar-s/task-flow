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

## 0. Ingest
Read the ticket **and every comment** in the tracker — the real DoD and the
"важное уточнение" often live in a late comment, not the title. Assign the task
to the user if it is not already. Restate the DoD and constraints back in one
short paragraph so scope is explicit. If scope genuinely forks, ask **now**
(AskUserQuestion) — not after implementing.

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
the `[PREMORTEM_EDGES]` slot of the phase-6/6b review dispatches. Phase 4's
plan premortem stays inline regardless — it attacks execution mechanics, not
the design.

## 3. Execution plan
Turn the corrected design into ordered, concrete steps: files to touch, tests to
write, migrations, grants, docs, deploy + cache-flush steps.

## 4. Premortem #2 — on the plan
Attack the plan the same way: wrong ordering, a mutation that commits before a
guard, a missing grant/migration, an un-flushed cache, an untested edge. Fix.

## 5. TDD implement
Branch off the integration branch (`fix/…` or `feature/…`, one branch per task).
Implement to the DoD. Write feature/unit tests that encode the DoD and the
premortem edge cases. Run the project's **test + static-analysis + lint** to
green. Keep spec-adjacent docs (API reference, OpenAPI) in the same change.

## 6. Code-review (adversarial)
Run an independent, adversarial review of the diff — the `code-review` Workflow
at high effort, or a **fresh reviewer subagent** dispatched with
[references/code-review-prompt.md](references/code-review-prompt.md).
Independence is structural, not aspirational: the reviewer receives the flow's
artifacts — diff range (`git merge-base HEAD <integration-branch>` → `HEAD`),
DoD, design-spec, premortem edge lists — and **never the session transcript,
the implementation story, or the author's framing of what is "fine"**. A
reviewer briefed on the author's doubts inherits the author's blind spots: it
checks the five things you already worry about and skips the sixth you missed.
The review is read-only on the checkout (rules in the template). Treat findings
as suspects: fix the **real** correctness/security/grant/transaction ones and
add a test that would have caught each; dismiss noise with a one-line reason.
Fixes to Critical/Required findings go back through a fresh review of the delta
(same clean dispatch) until none remain — a fix is a new change, not an
epilogue.

## 6b. Security-review (conditional)
Run an **independent** security pass on the diff (`/security-review`, or a fresh
subagent dispatched with
[references/security-review-prompt.md](references/security-review-prompt.md) —
never the agent that implemented it, same clean-context rule as phase 6). A
distinct threat-model lens, not a correctness re-run: STRIDE walked from the
trust boundaries the diff touches — authz/permission bypass, injection
(SQL/command/template), SSRF, unsafe deserialization, secrets committed to
code, missing grants; on AI/agentic surfaces, prompt injection and the OWASP
LLM Top 10. **Critical/High findings require a PoC or a concrete exploitation
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
  Force-push protection is a platform rule (protected branch), not a pipeline
  job. Merge, deploy to dev, flush the caches the change touches.
  - Scaffold this deterministic gate into a repo once with the **`ci-gate`**
    skill (part of this plugin) — it drops `ci/`, the gitleaks + pre-commit
    config, the platform CI file, and prints the protected-branch commands.
- Post a **"что сделано"** comment to the tracker: what shipped (per surface),
  how it was verified (tests + live), the MR/PR links, and any follow-ups.
- Set state **Done** and log **Spent time**.
- If the work spans surfaces (e.g. backend + frontend), create/link the paired
  ticket and note it.

## Fixed discipline (non-negotiable)
- One task = one feature branch off the integration branch → one MR/PR.
- CI pipeline **green before merge**; if a prior merge was blind, that is the bug.
- Never commit `Co-Authored-By` trailers unless the project asks for them.
- Never hand-edit tracker/migration bookkeeping tables; use the proper commands.
- Watch monorepo/symlink traps: stage the **real** file path, not a symlinked one.
- Report honestly: if a step was skipped or a test failed, say so with the output.
- Confirm outward-facing / irreversible actions (deploys, merges, external
  posts) unless the project has durably authorized them.
