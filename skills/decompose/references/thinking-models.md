# Thinking models — reasoning checks for the decompose phase

Adapted from Open GSD (see `../NOTICE.md`). Apply these at the point where a spec
is turned into a task graph — not as a running commentary, and not on every single
task. Each model exists to counter one specific way decomposition goes wrong; pick
the one that matches the failure you're worried about.

## Pre-mortem

**Counters:** a task breakdown that only accounts for the happy path, because
nobody deliberately imagined it going wrong.

Before treating the graph as final, assume the plan has already failed and name
the three most likely causes — a dependency nobody scheduled, a task boundary drawn
in the wrong place, a piece of work whose size was badly underestimated. For each
cause, add either a mitigation step or an acceptance criterion in some task's `dod`
that would have caught the failure early rather than at the end.

## MECE at the requirement level

**Counters:** two tasks quietly fighting over the same piece of work (merge pain),
or a requirement that never got a task at all (a silent gap).

Check the graph is mutually exclusive and collectively exhaustive against the
requirements, not against the tasks themselves: walk every requirement from the
spec and confirm it maps to exactly one task's `dod`. If two tasks touch the same
file, confirm they're serving two different requirements — not the same one split
in an arbitrary place. Anything left with zero owning tasks gets flagged before the
graph is considered done.

## Constraint-first

**Counters:** the riskiest part of the work getting scheduled last, so its failure
shows up only after everything else has already been built on top of it.

Find the single hardest constraint in this batch of work — the one piece that, if
it turns out not to work, makes the rest of the plan moot. Put that constraint into
one of the first one or two tasks in the graph, not near the end. If it depends on
an external system or a library nobody on the team has touched before, carve out a
small spike task to de-risk it ahead of the main implementation, rather than
discovering the unknown mid-build.

## Curse-of-knowledge counter

**Counters:** a task description that reads clearly to the person who wrote it, but
is ambiguous to whoever actually implements it, because the author's context never
made it into the words.

Re-read each task's `context` and `requirements` as if you've never seen this
codebase before. Is every noun specific enough to locate — which file, which
function, which endpoint? Is every verb specific enough to act on — added where,
changed how? If a sentence could reasonably be read two different ways, rewrite it
so it can't. A task description should carry enough concrete detail (paths, names,
expected behavior) that "the codebase is unfamiliar" is never an excuse for getting
it wrong.

## When not to think

These models cost time and attention, so skip them when they wouldn't change
anything:

- **Single-task cuts** — if the work reduces to one task with one clear
  requirement, there's no graph to check for gaps and no constraint ordering to
  reason about. Write the task and move on.
- **Well-understood, boilerplate work** — a version bump, a config tweak, a
  routine documentation update. There's no unfamiliar constraint to front-load and
  no realistic failure mode worth a pre-mortem.

Run the relevant model only when the plan is genuinely non-trivial and the
specific failure it counters is a real possibility — not as a ritual on every pass.
