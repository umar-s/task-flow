# Splitting reference — SPIDR axes and size signals

Adapted from Open GSD's SPIDR rules (see `../NOTICE.md`) for this plugin's
task/epic model. Use this reference from Phase 2 of the `decompose` skill
whenever a capability or a draft task looks too big to hand to one
implementer as-is.

## When to split a capability

Treat any of the following as a signal that a capability needs to be broken
apart before it becomes a task:

- **Bundled "and" capability** — the description strings together two or
  more independent user actions with "and" (for example, a single line that
  covers signing up, authenticating, *and* recovering a forgotten password).
  Each conjunction is a candidate seam.
- **More than one actor** — the description names more than one role (for
  example "shopper or store admin"). Treat each named role as its own
  candidate split.
- **Oversized description** — written out in full, the capability statement
  runs past what reads comfortably on one line (roughly 120 characters is
  the rule of thumb).
- **Vague noun-phrase capability** — the capability is phrased as a bare noun
  ("dashboard access") rather than a concrete verb + object ("filter the
  dashboard by date range"). A noun phrase means the actual interaction
  hasn't been pinned down yet.

If none of these signals fire, skip splitting and draft the task as-is.

## SPIDR — five axes, one per split

Once a split is warranted, pick exactly **one** of the five axes below and
apply it. Then look at the resulting pieces again before deciding whether a
further split is still needed — never combine two axes in the same pass.

### Spike — is something unknown?

Probe question: is there a piece of research or investigation that has to
happen before implementation can even be planned?

If yes: carve the unknown out as its own task. Its only exit condition is
that enough is now known to plan the rest of the work — it carries no other
acceptance criteria. Everything else becomes follow-on work once that
unknown is resolved.

### Paths — main flow vs. edge cases?

Probe question: is there one primary successful flow plus one or more
exceptional or error flows?

If yes: the primary flow becomes the first task, since it is what proves the
capability actually works end to end. Exceptional and edge flows become
follow-on tasks, ordered by how often they occur or how much damage they do
if left unhandled.

### Interfaces — more than one surface?

Probe question: does this capability have to exist on more than one surface
(web, API, CLI, mobile, and so on)?

If yes: split by surface. Whichever surface end users touch directly goes
first; a surface built mainly for machine-to-machine integration can come
after; a surface that isn't how most users will reach the capability goes
last.

### Data — more than one scope?

Probe question: does the capability have to handle more than one data scope
(a single record vs. many, one tenant vs. every tenant, a small sample vs.
the full dataset)?

If yes: split by scope, smallest first. Prove the capability against the
narrowest scope, then widen it in follow-on tasks.

### Rules — can the logic land in layers?

Probe question: can the business rules ship incrementally — bare-bones
validation now, richer policy later?

If yes: ship the minimum viable rule set first and defer the more elaborate
policy to a later task.

## Anti-patterns to reject

- **Horizontal, layer-by-layer splits.** Slicing by architecture tier —
  one task for schema, one for API, one for UI — is not a vertical slice:
  none of the resulting pieces is independently demonstrable end to end.
  Reject this shape whenever someone proposes it.
- **Splitting pre-emptively.** Don't split before checking whether any of
  the "when to split" signals actually fired. Most capabilities are fine
  as a single task.
- **Stacking more than one axis in a single pass.** If a capability trips
  two signals at once — say, both Paths and Data — resolve one axis first,
  then re-evaluate the smaller pieces before deciding whether a second split
  is still needed.

## Task-level split signals

Beyond the capability-level triggers above, watch for these once a
capability has already become a draft task — they suggest the task itself
is still too large to execute as one unit:

- `story_points` estimated above 8. This is a prompt to reconsider the task's
  boundaries, **not** an automatic re-split rule — story points are an
  optional annotation here, never the mechanism that drives a split
  decision.
- The task touches more than roughly five files.
- The task spans more than one subsystem or service.
- The task mixes a verification/checkpoint step in with actual
  implementation work. Pull the checkpoint out as its own step, or move it
  to the end of a task whose scope is otherwise clean.

Treat all of these the same way as the capability-level signals above: a
prompt to scrutinize the boundaries, not a mechanical formula. When a split
is actually warranted, it still runs through the same SPIDR axes described
above.

## Background

For outside context on vertical-slice splitting in general (not specific to
this plugin or to Open GSD), see Mike Cohn's write-up on splitting user
stories on the Mountain Goat Software blog.
