# Edge-probe reference — surfacing edge cases at spec time

Adapted from Open GSD (see `../NOTICE.md`). Use this reference during Phase 0/1 of
the `decompose` skill, while requirements are still being gathered — before any
task's `dod` is written down.

## Why this runs before decomposition, not after

A `dod` can only assert what someone thought to write down. If a requirement never
mentions what happens at an empty list, or at the boundary of a numeric range, then
no acceptance criterion for that behavior will ever exist, and no reviewer or QA
pass will catch its absence — there's nothing written to check against. Silence in
the requirement becomes an invisible gap in the `dod`, not a visible failure.

The fix is to push the question upstream: run every requirement through a small,
closed set of edge categories while the spec is still being drafted, so a missed
edge case turns into an explicit line in the requirement (or an explicit, reasoned
dismissal) rather than a defect nobody was watching for.

## Relevance filter first

Don't run all eight categories against every requirement — most won't apply, and a
probe that produces mostly "not applicable" noise gets ignored. Instead:

1. Classify each requirement by its dominant shape: `numeric-range`, `collection`,
   `text`, `stateful`, or `io`. A requirement can carry more than one shape.
2. Only raise the categories below whose applicable-shapes column matches. A
   requirement that is purely textual doesn't get asked about numeric overflow; a
   stateless read doesn't get asked about idempotency.

This keeps every raised category meaningfully connected to the requirement in
front of you, so an unresolved category is a real gap, not a checkbox nobody
expected to matter.

## The eight categories

| category | applicable shapes | probe question |
|---|---|---|
| boundary | numeric-range | At the minimum, the maximum, and each threshold — plus one step to either side — what is the required behavior? |
| adjacency | collection | When two elements land at the same point, or exactly touch, do they merge, collide, or stay separate? |
| empty / degenerate | collection, text | What must happen when the input is empty, has exactly one element, or is null? |
| encoding | text | Which unit decides "length" or "equal" here — raw bytes, code points, grapheme clusters, or a normalized form? |
| ordering / stability | collection | When two elements are equivalent under the comparison rule, is their relative order guaranteed and stable? |
| precision / overflow | numeric-range | Where could rounding, truncation, or overflow occur, and which convention governs ties (up, down, to-even)? |
| idempotency | stateful | Does running the same operation a second time, against otherwise unchanged state, produce the same result as running it once? |
| concurrency | stateful, io | If the operation is interrupted partway, or two instances run at the same time, what is still guaranteed? |

## Resolving what gets raised

Every category raised by the relevance filter needs one of three outcomes before
the requirement is considered spec-complete:

- **Addressed** — the requirement text is updated (or an acceptance criterion is
  added) so the behavior is explicit. This is the target outcome, and it's what
  turns into a checkable line in the task's `dod` once the requirement becomes a
  task — including a `truths` entry when the assertion is the kind of fact a
  goal-backward check can verify directly.
- **Dismissed with a reason** — the category genuinely doesn't apply beyond what
  the shape classification already caught (for example: "no boundary case — the
  input is a two-value enum"). The reason string is mandatory and is what makes the
  dismissal auditable later; a category left blank with no reason is treated as
  unresolved, not as dismissed.
- **Left open** — carried forward as a known gap and flagged in the draft, rather
  than silently dropped. An open edge is a visible risk the author accepted, not an
  invisible one nobody noticed.

Silence is the one outcome that is never acceptable: every applicable category
gets an explicit answer, even if that answer is "doesn't apply, because...".

## Small worked example

Requirement: "Assign each newly created support ticket to an available agent,
round-robin across the team." Classified shape: `stateful` (assignment changes
persistent state) plus a touch of `collection` (rotating across a team list).

Raised categories: `idempotency` (creating the same ticket twice — does retry
duplicate an assignment?), `concurrency` (two tickets arriving at once — do they
ever land on the same agent, or race past each other?), `empty / degenerate` (what
happens when the team has zero available agents?), and `ordering / stability`
(does round-robin position persist correctly if the team roster changes mid-cycle?).

Each of those four gets addressed, dismissed with a reason, or explicitly left open
before this requirement is handed to decomposition — at which point an addressed
edge becomes one more line in the resulting task's `dod`.
