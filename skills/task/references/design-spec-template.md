# Design-spec template (phase 1)

Loaded in phase 1. The spec is what the premortems attack, what the reviewer
compares the diff against, and what survives a `/compact`. Write it in the
project's artifact directory (the path the project's `CLAUDE.md` names, else
next to the ticket's branch: `docs/specs/<TASK-ID>.md`), then confirm it will
survive a checkout: `git ls-files --error-unmatch <path>` or
`git check-ignore -v <path>` — an ignored spec is a spec you will lose.

**Scale by tier, never by taste.** T1: three sentences in the ticket, no file —
Problem, DoD, Reversibility if it is one-way. T2: sections 1–6. T3 / any
one-way door: every section, and §5 is not optional.

A section with nothing to say is written as "none, because …". An **absent**
section reads to the reviewer as an oversight, and to the next session as a
decision that was never made.

---

## 1. Problem
What is wrong or missing today, in the user's terms, and what the ticket asks
for. One paragraph. If the ticket text and the observed behaviour disagree, say
so here — that disagreement is usually the real task.

## 2. Scope / Not in scope
Two lists. "Not in scope" is the one that saves the review: anything the diff
touches that is not in the first list is scope drift the reviewer must flag.

## 3. Context pack
What you actually read before deciding, as `path:line` — the seam you will
change, its callers, the test that covers it, the migration that shaped the
schema. Not a file tour: the three to eight places that decided the design.
This is also the reviewer's map of what you *did not* read.

## 4. Decisions & assumptions
Each decision: what you chose, what you rejected, and the fact that decided it
(a measurement, a constraint from the project's CLAUDE.md, a line of code).
Assumptions are marked as such, with what would falsify each one. A decision
without a rejected alternative is a preference, not a decision.

## 5. Reversibility (required for one-way doors, T3, and every migration)
- **Class:** `two-way` (revert the commit and it is over) or `one-way`
  (migration, persistent data, a public API or event contract, a security
  boundary, a coordinated rollout across services).
- **Rollback:** the exact way back — command, who runs it, how long it takes.
  "Revert the MR" is only true when no data has moved.
- **Stop condition:** the signal that says roll back rather than push forward,
  named in advance (error rate, queue depth, a failing invariant query).
- **Compatibility window:** while old and new code run together — which
  requests, jobs, or messages see which shape, and what breaks if a client
  stays on the old one.

What does **not** count, because it reads like a plan and is not one: a
rollback that does not bring the data back ("revert the MR" after a column was
dropped); a stop condition without a metric, a threshold and someone watching
it; a compatibility window that does not say what old code does with the new
shape *and* what new code does with the old one. Write "no rollback: this is
one-way, the mitigation is X" rather than a rollback that would not work — a
false rollback is worse than an admitted one, because it gets believed at 3am.

## 6. DoD → check table
Restate the DoD as a numbered checklist; every item gets a class of
verifiability, and the class decides what "done" may mean:

| # | Definition of done | Class | How it is checked |
|---|---|---|---|
| DoD-1 | … | `diff` | the code itself: `path:line` |
| DoD-2 | … | `live` | a command or user path, run after deploy |
| DoD-3 | … | `external` | outside this repo (DNS, a provider, another team) — the manual check and who does it |

An item nobody can verify is a question for the ticket, not an assumption you
carry. `external` items close as **UNVERIFIABLE with a named manual check** —
never as done "because the code handles it".

## 7. Premortem edges (filled in by phases 2 and 4)
The failure modes the premortems found, one line each:
`mode | test? | handled? | user sees it?`. Three "no" in a row is a design fix,
not a note. This section is what the phase-6 dispatch reads for
`[PREMORTEM_EDGES]`, so it has to live here, on disk, not in the session.

## 8. Failure signal
How you will find out in production that this change broke something: the log
line, metric, alert or user report to watch, and for how long. If the honest
answer is "we would not find out", that is the most valuable sentence in the
spec — and usually the cheapest thing to fix.
