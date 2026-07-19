---
name: decompose
description: >-
  Turn one large unit of work — a free-text feature description, an existing
  tracker epic `<TASK-ID>`, or a spec/design doc — into well-formed, linked
  tasks (name, context, requirements, DoD with truths, story points,
  depends_on) with a dependency graph and parallelism waves. Produces a
  self-contained MD draft for review; on approval, an optional dry-run-first
  tracker push (generic adapter, no tracker configured → stop at the draft).
  Use when the user invokes /decompose, or asks to "нарежь на задачи",
  "декомпозируй эпик/фичу", "разбей проект на задачи", or otherwise wants an
  epic/feature/spec cut into a task breakdown. Runs **before** `task` — each
  produced `<TASK-ID>` is then executed end-to-end by `task-flow:task`.
---

# Epic/feature → task breakdown flow

A single pass that takes one large unit of work from a rough description (or
an existing epic, or a spec doc) to a reviewed, dependency-graphed task
breakdown the user can push into a tracker. The **discipline below is
fixed**; the **concrete commands are project-specific** — read the project's
`CLAUDE.md` first and map each "resolve from CLAUDE.md" step to the real
binding there.

**Argument:** free description | existing tracker id `<TASK-ID>` | path to a
spec/design doc. Auto-detect which of the three was given — a bare path that
resolves to a file is a spec doc, a short token matching the project's
tracker-id shape is an existing epic, anything else is a free description.
Never assume a specific tracker's id prefix (no hardcoded `BA-`/`DEV-`/etc.
pattern) — resolve the real shape from the project's tracker binding if you
need to disambiguate.

**Setup:** create one todo per phase (0–7) so progress is visible, and mark
each done as you go. Do the phases in order — do not skip Phase 5 (QA) or
Phase 4 (graph/waves) because the breakdown "looks obviously right"; that is
exactly when a missing dependency or an uncovered requirement hides.

## Reference loading (resolve once, read lazily per phase)

Most phases below name a reference file under this skill's `references/`
dir. Resolve the base path **once**, at the start, with a bash step:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "<this SKILL.md's own path>")/../.." && pwd)}"
echo "$ROOT"
```

`CLAUDE_PLUGIN_ROOT` is set when this runs as an installed plugin; the
fallback walks up from this file's own location when it doesn't (e.g. a
working copy outside the plugin harness). Either way, `$ROOT` ends up an
**absolute path on disk**, and every reference load for the rest of this
session is:

```
Read "$ROOT/skills/decompose/references/<file>.md"
```

using the **resolved value of `$ROOT`**, substituted in before the Read
call — never pass the literal string `${CLAUDE_PLUGIN_ROOT}` to the Read
tool; it does not expand shell/env syntax, so a literal pass fails or reads
nothing. Do this resolution exactly once per session, then reuse `$ROOT` for
every subsequent Read.

Load references **lazily, one phase at a time** — don't front-load all seven
before Phase 0 starts. Phase 0 only needs `references/edge-probe.md`;
Phase 2 doesn't need `references/qa-checklist.md` yet; and so on. This keeps
context spent on the reference that's actually in play.

## Project bindings — resolve these from CLAUDE.md before starting

- **Tracker** (optional) — how to create an issue/epic, link `parent` and
  `depends` relations, and which fields map to `story_points`/estimate. Absent
  entirely on a fresh install — that's fine, see Phase 7.
- **Draft location** — where decomposition drafts live; default
  `docs/decompose/YYYY-MM-DD-<epic>.md` if the project states no override.
- **Project context sources** — where requirements/specs/prior decisions
  normally live (README, `docs/`, project memory) so Phase 0 reads the right
  places instead of guessing.

## 0. Ingest & scope
Read the project context first: `CLAUDE.md`, project memory, and whichever
existing docs/specs are relevant to the input. If the input is an existing
tracker epic or a spec path, read it in full before anything else. If
requirements are genuinely missing or too vague to decompose (a bare
one-line ask), extract them — goal, why, for whom, what "done" means — then
run each extracted requirement through the edge-case categories in
`references/edge-probe.md` (load it now, per the resolved `$ROOT`). Keep
this brief and targeted, not an interview: only raise the categories
`references/edge-probe.md`'s relevance filter says apply to that
requirement's shape.

## 1. Requirements
Turn what Phase 0 gathered into a numbered `REQ-NN` list: each requirement
user-centric, testable, and atomic (one requirement, one testable claim).
Build the traceability seed here — every `REQ-NN` must map to at least one
task by the time Phase 2 finishes; a requirement with no owning task by
Phase 5's QA pass is a BLOCKER, not a detail to fix later.

## 2. Decompose
Break the requirements into tasks **dependency-first, not sequence-first**:
for each candidate task, name what it *needs* (inputs from other tasks) and
what it *creates* (what later tasks can depend on) before deciding on
ordering. Cut **vertical slices** (a thin end-to-end capability) — never
horizontal layers (e.g. "all models," then "all endpoints," then "all UI"
as separate tasks). Load `references/splitting.md` for the SPIDR axes and
size signals, and apply exactly one axis per split. Load
`references/thinking-models.md` and run pre-mortem, MECE-at-requirement-
level, and constraint-first against the resulting graph.

**Scope-reduction prohibition:** a task description carrying "v1,"
"placeholder," "stub," or "basic version for now" is not a smaller task —
it's a hidden requirement gap. Split it into an explicit follow-up task
instead of quietly shrinking the DoD.

**Splitting is driven by SPIDR / vertical slices / dependencies — never by
story points.** Size (Phase 3's `story_points`) is computed *after* a task
is already well-formed; it never decides whether or how to split one.

## 3. Enrich
Fill in the **6 author fields** for every task, per
`references/task-schema.md` (load it now): `name` (verb + object, not a bare
noun), `context` (why, `@`-references to code/decisions/related tasks),
`requirements` (its `REQ-NN` list, non-empty), `dod`, `story_points`,
`depends_on`. `dod` is a 4-member block —
`done`, `acceptance_criteria`, `verify`, and `truths` (goal-backward,
user-observable facts) — all four required; a `dod` missing `truths` is
incomplete, not optionally short. `story_points` is a Fibonacci estimate
(`1/2/3/5/8/13`) and is an **optional annotation, not a gate** — don't let it
drive any decision made back in Phase 2.

## 4. Graph & waves
Build the `depends_on` graph across all tasks and check it's acyclic — a
cycle (direct or transitive self-dependency) is fixed here, before QA ever
sees it. Compute each task's `wave` (`wave = max(dependencies' wave) + 1`,
tasks with no dependencies are wave 1) — this is a **computed** field, never
hand-authored. Roll up `story_points` across the epic as an informational
total (not a commitment), and note the wave count as the breakdown's
parallelism width.

## 5. QA
Dispatch an **independent** subagent, via the Agent tool, in a **fresh
context** — it must not have seen Phases 0-4 run, so it has no attachment to
the breakdown it's grading. Load `references/qa-checklist.md` now and hand
its full text as that subagent's brief, along with the `REQ-NN` list and the
full task breakdown (all 6 author fields + computed `wave` per task). The subagent runs the 7
checks (requirement coverage, field completeness, graph acyclicity,
atomicity, key-links, no silent scope reduction, MECE) and reports BLOCKER/
WARNING findings.

On any BLOCKER, revise the breakdown (back to whichever of Phases 1-4 the
finding traces to) and re-check with the same subagent. **Loop until a
check-run returns zero BLOCKERs — that clean run is the only exit; never stop
on a cycle count.** Cap the *fix-rounds* at **3** as a runaway backstop, but a
check-run always follows the last fix-round, so no fix ships without a
verifying run behind it. If BLOCKERs still remain on the check-run after the
3rd fix-round, escalate to the user per `references/qa-checklist.md`'s
non-convergence rule (list open BLOCKERs, flag UNVERIFIED fixes, read
persistent non-convergence as a likely-underspecified epic/requirements)
rather than forcing more automatic passes. WARNINGs alone never block the exit.

## 6. Draft
Load `references/draft-template.md` and write the epic header, task table,
one card per task (all 6 author fields; `wave` shows only in the table/graph, not on a
card), the dependency graph (mermaid), and the traceability table into
`docs/decompose/YYYY-MM-DD-<epic>.md` (or the project's configured draft
location). This MD file is the **self-contained primary artifact** — even if
Phase 7 never runs, this is a complete deliverable on its own.

**Stop here and get explicit user approval** on the draft's content before
going anywhere near Phase 7. "The skill finished running" is not approval;
the user reviewing (and, if needed, editing) the actual tasks/fields/graph
is.

## 7. Tracker sync (optional)
Only after Phase 6's explicit approval. Load `references/tracker-sync.md`
and follow it exactly: resolve the tracker binding from `CLAUDE.md`,
discover the concrete MCP tools via ToolSearch (never hardcode a tool name), and if no tracker is
configured or reachable in this session, stop gracefully at the draft — that
is the expected shape of a fresh install, not an error.

If a tracker is reachable: **default to dry-run** — render and print the
full create/link plan (every summary, description, estimate + fallback rung,
link, and stable idempotency key) with **zero writes**, and get the user's
confirmation on that plan. Only after confirmation, re-run the same plan
with writes enabled (create-or-update by idempotency key, then `parent` and
`depends` links). On any mid-way failure, stop and report — do not keep
creating tasks past a failed one.

Return the list of created/updated `<TASK-ID>`s (or, if Phase 7 didn't run,
the draft path and the `<TASK-ID>` placeholders used in it).

## Handoff
Each produced `<TASK-ID>` is executed end-to-end, one at a time, by
`task-flow:task` — that skill's own ingest phase reads the ticket and takes
it from there. `decompose` stops the instant a well-formed draft (and,
optionally, a well-formed set of tracker issues) exists; running any task is
not this skill's job.

## Fixed discipline (non-negotiable)
- Splitting axis is SPIDR/vertical-slices/dependencies — story points are an
  annotation computed after the fact, never a splitting trigger.
- Every task's `dod` carries all four members including `truths`; a task
  missing `truths` is incomplete, not "good enough."
- Phase 5's QA subagent runs in a fresh context, independent of the phases
  that produced the breakdown — never skip it, never let the same context
  that authored the breakdown also grade it.
- The MD draft is the primary artifact regardless of whether a tracker is
  ever configured; never make the draft conditional on Phase 7 succeeding.
- Phase 7 never writes to a tracker without an explicit dry-run the user
  confirmed first, and never assumes a tracker's id-prefix shape anywhere in
  this skill's own contracts.
- Report honestly: if QA hit the fix-round cap with BLOCKERs still open
  (non-convergence), or a tracker push partially failed, say so with the
  actual findings/output.
