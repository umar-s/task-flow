# Task schema reference — canonical field names for `decompose`

Adapted from Open GSD (see `../NOTICE.md`). This is the single source of truth
for task field names in this plugin. Phase 3 (enrich) fills these fields in,
the QA checklist (subagent checker) grades a task by whether they're all
present, the draft template renders them into the MD draft, and tracker-sync
maps them onto whatever adapter is configured. Every one of those consumers
reuses the exact names below — nobody invents a synonym, and nobody's field
count disagrees with another's.

## The canon

**6 author fields, plus `truths` nested inside `dod`, plus a computed `wave`.**

- The **6 author fields** — filled in by whoever is decomposing the epic —
  are: `name`, `context`, `requirements`, `dod`, `story_points`, `depends_on`.
- `truths` is **not** a 7th author field sitting next to those six. It lives
  **nested inside `dod`**, alongside `dod`'s other three members (`done`,
  `acceptance_criteria`, `verify`). A task's `dod` block always has all four;
  a task missing `truths` has an incomplete `dod`, not a missing optional
  extra.
- `wave` is **not** authored at all. It's a number **computed from the
  `depends_on` graph in Phase 4** (parallelism grouping), written onto the
  task after decomposition, never typed in by hand during Phase 2/3.

Put together: 6 fields an author writes, one of which (`dod`) internally
carries `truths` as a fourth member, plus one field (`wave`) that shows up
later from graph analysis, not from authoring. Any consumer describing this
schema says "6 author fields, `truths` inside `dod`, computed `wave`" —
never "6 fields" (which silently drops `truths`), never "8 fields" (which
wrongly promotes `truths` and `wave` to author-field status).

## Field table

| Field | Contains | Origin |
|---|---|---|
| **name** | Action-oriented task name: verb + object, not a bare noun phrase (e.g. "Implement POST /login endpoint", not "Login"). | GSD `<name>` |
| **context** | Why the task exists, `@`-references to the code/decisions/conventions it must follow, and pointers to related tasks. | GSD `<context>` / `<read_first>` |
| **requirements** | The `REQ-NN` identifier(s) this task covers. Must be non-empty — every task traces back to at least one requirement. | GSD `requirements` |
| **dod** | Definition of Done — a 4-member block: `done`, `acceptance_criteria`, `verify`, `truths`. See below. | GSD `<done>` / `<acceptance_criteria>` / `<verify>` + `must_haves.truths` |
| **story_points** | Fibonacci estimate — `1`, `2`, `3`, `5`, `8`, or `13`. **Optional annotation, not a gate.** `story_points` > 8 is a WARNING to reconsider the task's boundaries, never an automatic re-split trigger — splitting is driven by SPIDR / vertical slices / dependencies, not by this number. | Added in this plugin — GSD's estimation model has no equivalent. |
| **depends_on** | List of prerequisite task IDs. May be empty for a task with no predecessors, but the field itself is always present. | GSD `depends_on`, extended from per-plan to per-task |
| **wave** | Parallelism wave number. **Computed from the `depends_on` graph in Phase 4 — not an author field.** Never hand-written during decomposition; it's derived once the full dependency graph is known. | GSD `wave` |

## `dod`'s four members

`dod` is not a single string — it's a small block with four members, all
required:

| Member | Answers | Shape |
|---|---|---|
| **done** | What observable state means this task is finished? | A short, measurable description (e.g. "valid creds → 200 + JWT cookie; invalid → 401"). |
| **acceptance_criteria** | How would a reviewer check `done` mechanically? | A list of grep-verifiable or otherwise mechanically checkable conditions — not "works correctly," but "file X contains string Y." |
| **verify** | What single command proves it, right now? | An actual command, expected to run in under ~60s (e.g. `pnpm test auth/login.test.ts`). |
| **truths** | What can an end user now observably do, that they couldn't before? | A list of goal-backward, user-observable facts (e.g. "User can log in with email+password"). This is the same idea as GSD's `must_haves.truths`, scoped down to one task instead of one phase. |

`done`/`acceptance_criteria`/`verify` check that the *implementation* is
correct; `truths` checks that the *goal* was actually reached — a task can
satisfy the first three by shipping a stub and still fail `truths` if nothing
a user cares about actually changed. A `dod` block missing `truths` is
incomplete, full stop — this is exactly the gap the QA checklist's
field-completeness check (BLOCKER) exists to catch.

## Worked example

A fully filled task, taken from a hypothetical auth epic. Every field is
populated with realistic values; `depends_on` is non-empty, `story_points` is
mid-range, and `dod` carries all four members including `truths`.

```markdown
### T3: Implement POST /login endpoint

- **name:** Implement POST /login endpoint
- **context:** Auth epic needs a session-issuing endpoint before the
  dashboard route guard (T4) can gate access on a real session. Follow the
  password-hash convention already established in the User model
  (@src/models/user.ts, from T1) and the cookie options used by the
  session-refresh endpoint (@src/api/session/refresh.ts). Related: T1 (User
  model — provides `User.verifyPassword()`), T4 (dashboard route guard,
  depends on this task's cookie).
- **requirements:** [REQ-02]
- **dod:**
  - **done:** Valid credentials return `200` with a `Set-Cookie: session=<jwt>`
    header (`httpOnly`, `maxAge: 900`); invalid credentials return `401` with
    no cookie set.
  - **acceptance_criteria:**
    - `src/api/auth/login.ts` contains `maxAge: 900`
    - Response for valid credentials includes a `Set-Cookie` header
    - Response for invalid credentials is `401` and omits `Set-Cookie`
  - **verify:** `pnpm test auth/login.test.ts` passes (<60s)
  - **truths:**
    - "User can log in with email + password"
    - "Wrong password is rejected, not silently accepted"
- **story_points:** 3
- **depends_on:** [T1]   <!-- T1 = User model, provides verifyPassword() -->
- **wave:** 2   <!-- computed in Phase 4: T1 is wave 1; T3 depends on T1, so wave 2 -->
```

Note that `wave: 2` here is written only because Phase 4 has already run its
graph computation for this worked example — during Phase 2/3 authoring, a
real task would carry `name` through `depends_on` and leave `wave` unset
until decomposition finishes.
