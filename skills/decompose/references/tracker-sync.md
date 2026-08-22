# Tracker sync reference — Phase 7's optional, generic tracker push

This is the runtime procedure Phase 7 of the `decompose` skill follows, and
only Phase 7 — nothing here runs during Phases 0-6. The MD draft
(`draft-template.md`, written in Phase 6) is already the self-contained
primary artifact; everything below is an optional extra a user can decline
entirely. It is also the single riskiest step in this skill: every other
phase reads inputs and writes one local file, but this phase writes to a
shared tracker that other people and other tools treat as source of truth.
Treat every rail below as load-bearing, not decoration — a decomposition
skill that writes duplicate or orphaned issues into someone's tracker has
done net-negative work even if the MD draft it started from was perfect.

Unlike `task-schema.md`, `qa-checklist.md`, `splitting.md`,
`edge-probe.md`, and `thinking-models.md`, this file is **not** adapted
from Open GSD — GSD has no generic multi-tracker adapter, only an
interactive per-project sync loop. This procedure is native to
`task-flow`, written to satisfy one hard constraint: this plugin ships to
a public marketplace, so nothing in it may assume a specific tracker or
leak a private tracker's ID shape into a contract. `<TASK-ID>` below is a
placeholder throughout — never replace it in this file with a real
tracker's ID format (e.g. a private project-prefixed key); a real ID only
ever appears in a user's own session output, never in the reference that
ships to every install.

## 1. Adapter contract (generic, not YouTrack)

Phase 7 talks to exactly one adapter through a small fixed contract: two
write operations, one read, one optional search, and a declared markup. Any
tracker plugged in here — YouTrack, Jira, Linear, GitHub Issues — implements
the same contract; nothing in this file or in Phase 7's logic may assume
tracker-specific fields, states, or workflows outside of the illustrative
"YouTrack adapter" mapping in §7.

```
create_issue(summary, description, estimate?, parent?) -> <TASK-ID>
link(from: <TASK-ID>, to: <TASK-ID>, type: "depends" | "parent") -> ok
read_issue(<TASK-ID>) -> { summary, description, estimate?, parent?, links[], url? }
search_issues(query) -> [{ id: <TASK-ID>, summary, url? }]   # optional; query in the tracker's own language
describe_project(project) -> { issue_types[], fields[{ name, type }], link_types[], url_base? }   # optional; what preflight reads
markup: "markdown" | "jira-wiki" | "adf-via-markdown" | "plain"   # declared, default markdown
```

- `create_issue` returns the tracker's own issue id. That returned id is
  what Phase 7 substitutes for `<TASK-ID>` in its final return list (§10)
  — Phase 7 never invents an id itself.
- `estimate` and `parent` are optional on the call: a wave-1 task with no
  epic parent and no estimate field available still creates fine, it just
  omits those arguments.
- `link`'s `type` is a two-member enum Phase 7 needs: `"depends"` (native
  depends / is-required-for, task → task) and `"parent"` (subtask-of /
  parent-epic membership, task → epic). A tracker missing one of these
  link types natively degrades per §7's fallback rule — it does not block
  the rest of the sync.
- **`read_issue` is what makes a write verifiable.** An `ok` from
  `create_issue`/`link` is a claim by the side that did the writing — the same
  axiom that makes this plugin's gate deterministic applies here. §9 reads
  every created issue back and compares it with what was sent. `url?` is what
  §10 returns next to the id; an adapter without it falls back to the base
  URL the binding names plus the id, and says that it did.
- **`markup` is declared, not guessed.** Resolution order: a `markup:` line
  in the `CLAUDE.md` tracker binding; else the tracker family the binding
  names (Jira Server/DC → `jira-wiki` — it shows Markdown as literal
  asterisks; Jira Cloud → `adf-via-markdown` through an MCP tool that
  converts, `plain` over raw REST; YouTrack, Linear, GitHub → `markdown`);
  else `markdown`. The dry-run header prints `markup: <value> (from
  <source>)`, and a tracker that renders the result wrong is a finding to fix
  in the binding, not something to paper over per-issue.
- **`describe_project` is optional, but it is what preflight reads.** Without
  it the preflight proves only the token and the project: the dry-run then
  prints `metadata: unknown (adapter has no project read)` and pre-selects
  the lowest rungs — the `SP: N` line, textual links — instead of promising
  fields it cannot see.
- **`search_issues` is optional.** When present, §5's dry-run lists possible
  duplicates and §6's key lookup has something to look with; when absent — or
  when it errors — the dry-run says so and continues. The query is written in
  the tracker's own language (§7 shows YouTrack's): the adapter owns the
  syntax, Phase 7 supplies the words — the task's `name` — and the restriction
  to open issues in the target project. A duplicate check that blocks the
  sync would be a worse failure than the duplicate it prevents.
- **YouTrack is the first supported adapter — an example, not the
  contract.** Nothing about `create_issue`/`link` is YouTrack-shaped; §7
  shows how YouTrack's actual MCP tools satisfy this contract. A second
  adapter (Jira, Linear, GitHub Issues, ...) implements the identical
  contract against its own MCP tools — or its REST API (§3) — resolved the
  same way.

## 2. Preconditions — the approval gate

Phase 7 runs only after both of these hold. Neither is negotiable, and
dry-run mode (§5) does not bypass either — a dry-run is still Phase 7
running, just with writes disabled.

1. **Explicit user approval of the MD draft's content.** Not "the skill
   ran to completion" — actual sign-off that the epic, tasks, fields, and
   dependency graph in the draft are what should exist. The spec is
   explicit: the user reviews and edits the draft, and *only after that
   approval* does Phase 7 start (`docs/superpowers/specs/2026-07-18-task-flow-decompose-design.md`
   §8-9). Skipping straight to a tracker push "to save a round-trip" turns
   an unreviewed decomposition into permanent tracker state.
2. **A known target project / parent-epic id.** Either the user names it
   directly, or Phase 7 resolves a candidate from a `CLAUDE.md` tracker
   binding (§3) and then confirms it with the user before writing anything
   — never silently default to "whichever project the MCP happens to
   point at." Writing an epic's tasks into the wrong tracker project is as
   bad as not writing them at all, and harder to notice.

## 3. Runtime tool discovery

Same discipline as `task`'s "Project bindings — resolve these from
CLAUDE.md" section: read the concrete tracker binding from the project's
own `CLAUDE.md` first, never hardcode a tracker's tool names or API shape
into this skill.

1. Read the project's `CLAUDE.md` for a tracker binding (mirrors `task`:
   how to create/read/link issues, the project key, and any
   credential/token the binding names).
2. If `CLAUDE.md` names a tracker, use **ToolSearch** to locate the
   concrete MCP tools for it this session — e.g. `ToolSearch(query:
   "youtrack create issue")`, `ToolSearch(query: "youtrack link issue")`,
   `ToolSearch(query: "youtrack get issue")`, `ToolSearch(query: "youtrack
   search issues")`, `ToolSearch(query: "youtrack project fields")`. Tool
   names vary per MCP
   server build and version, so search for the capability rather than
   assume a literal tool name.
3. If `CLAUDE.md` names a tracker binding but ToolSearch finds no matching
   tool in *this* session (the MCP is attached to some sessions and not
   this one — e.g. a project session vs. a general one) — and the binding
   names no REST endpoint (step 4) — tell the user the tracker isn't
   reachable here and stop at the draft. Do not
   fabricate a call against a tool that doesn't exist in this session.
4. **No MCP, but the binding names a REST endpoint?** If `CLAUDE.md` gives the
   API base URL and the **name** of the environment variable holding the token
   (never the value: it is referenced only as `"$NAME"` inside the call — an
   `Authorization` header, not a query string — never echoed, never expanded
   into a command the transcript shows, never under `set -x`; an error body
   that echoes the request is truncated before it is printed), that REST API
   is a valid transport for the same adapter contract: the operations are the
   same, only the calls differ. The call itself: `curl -sS --fail-with-body`
   (an HTTP error must be a non-zero exit, never a silent `ok`), no `-v`,
   and `${NAME:?}` so an unset variable stops the run naming the *variable*.
   Keep the same rails — preflight, dry-run, idempotency key, read-back — and
   let the tracker's own bulk facility do the work where it has one (YouTrack's
   `/api/commands` sets links and estimate in a single call, for instance —
   one issue per call, so a failure still maps to one task). The binding
   declares `markup:` next to the endpoint (§1 gives the fallback order). A
   binding that names neither an MCP nor an endpoint goes to §4.
5. If `CLAUDE.md` defines **no** tracker binding at all, skip discovery
   entirely and go straight to §4.

## 4. No-tracker graceful stop

If discovery found neither a tracker MCP nor a REST endpoint — whether
`CLAUDE.md` has no tracker binding at all or a binding that names no
transport — that is not a failure condition — it is the expected shape of a
fresh install, or of any project session that simply has no tracker MCP
attached. Phase 7 stops here and says so plainly, once, in one sentence:
the MD draft at `docs/decompose/YYYY-MM-DD-<epic>.md` is the deliverable,
full stop, and tracker sync is a config-away optional extra the user can
wire up later. Never surface this path as an error, a stack trace, or a
retry loop — a public-marketplace plugin that crashes on "no tracker
configured" has confused its one truly optional phase for a required one.

## 5. Dry-run mode (default)

Dry-run is the default the very first time Phase 7 reaches a real,
resolved tracker adapter, and it is not skippable by silently defaulting
to "just write it" — the user must see the plan and confirm before any
`create_issue`/`link` call actually fires.

A dry-run prints the **full** create/link plan and performs **zero**
writes:

- The preflight summary first (§9 step 3): the project/epic id, `markup:
  <value> (from <source>)`, the issue types, fields and link types found — or
  `metadata: unknown (adapter has no project read)` — and the estimate rung
  that will be used, so the plan below promises only what exists.
- Every task's `summary` (from `name`), its full rendered `description`
  (from `context` + `requirements` + `dod` including `truths`, per §7),
  its resolved `estimate` value and which fallback rung produced it, and
  its stable idempotency key (§6).
- Every `link` call that would run: task → epic `parent` links and task →
  task `depends` links, listed by `<TASK-ID>` pair and type.
- Tasks whose fields still carry a `<placeholder: …>`, listed by id: they are
  pushed as written — this phase never fills a placeholder in — and stay out
  of dispatch until someone does.
- A one-line count at the end: how many `create_issue` calls and how many
  `link` calls the real run would make.
- **Possible duplicates**, when the adapter offers `search_issues`: for each
  task, up to three *open* issues whose summary looks like the same work, with
  their ids and URLs. It is a prompt for the human, never a decision this phase
  makes: the idempotency key (§6) is what prevents *this* skill from creating
  the same issue twice; this block is about what someone else already filed. A
  search that fails prints one line and the dry-run continues.

This is deliberately dual-purpose: it is the safety default before any
write touches a production tracker, **and** it is the acceptance-test path
for this whole phase — a reviewer (or an automated check) can validate the
entire mapping and link plan by reading dry-run output, without a tracker
even needing to exist. Only after the user has seen the dry-run plan and
explicitly says to proceed does Phase 7 re-run the same plan with writes
enabled.

## 6. Stable idempotency key

Every issue Phase 7 creates gets stamped with a marker of the shape:

```
decompose-id:<draft-slug>#<n>
```

- `<draft-slug>` is the MD draft's own slug (the `<epic>` portion of
  `docs/decompose/YYYY-MM-DD-<epic>.md`), so keys from two different
  decompositions never collide.
- `<n>` is the task's position/id within that draft (e.g. matching its
  `<TASK-ID>` in the draft, `T1`, `T2`, ...).
- The marker goes into a custom field if the tracker's adapter exposes
  one for it, otherwise as a plain line inside `description`.

On re-run, Phase 7 matches existing issues by **this key, not by
`summary` string.** An LLM regenerating a decomposition rarely reproduces
byte-identical task names, so matching on summary text would create a
second, duplicate set of issues every time the draft is regenerated and
re-pushed. Matching on the stable `decompose-id:...` key means: key found
→ update the existing issue in place; key missing → create a new one.
This is what makes a re-run safe by default, including the recovery path
in §8.

**The lookup needs a search.** Matching by key means querying the tracker for
`decompose-id:<draft-slug>#<n>` — through `search_issues` when the adapter
has it. A hit counts only after `read_issue` shows the exact key line in the
description (or the custom field): a fuzzy hit without it is not a match and
must never be updated. An adapter with no search has no way to find an
earlier run's issues — a re-run is then **not** idempotent, and the dry-run
says so before the user confirms.

## 7. Field & link mapping

| Draft field | Maps to | Notes |
|---|---|---|
| `name` | `summary` | Verbatim. |
| `context` + `requirements` + `dod` (incl. `truths`) | `description`, in the adapter's declared `markup` (§1) | Rendered as one block — converted from Markdown when the adapter declares `jira-wiki`, `adf-via-markdown` or `plain`: context prose first, then a `Requirements: [REQ-NN, ...]` line, then the `dod` block with all four members — `done`, `acceptance_criteria`, `verify`, `truths` — spelled out, not summarized, then a `Source: <draft path>, epic <ID or none>` line (the draft is the origin even when the input was free text). A reviewer reading the created issue alone should see the same DoD the MD draft showed, and can find the draft it came from. |
| `story_points` | `estimate` (fallback ladder) | See below. |
| `depends_on` | `link(..., type: "depends")` | One link per entry, task → task. |
| epic membership | `link(..., type: "parent")` | One link per task, task → epic. |
| (Phase 7 only) | `decompose-id:<draft-slug>#<n>` marker | §6 — stamped on every created issue, not a draft field. |

**Estimate fallback ladder** (`story_points`, always present as an
annotation, never a gate — per `task-schema.md`): try each rung in order
and **log which one was used**, since silent fallback makes a later
"why didn't the estimate show up as a number" report unnecessarily
mysterious:

1. A native **estimate** field on the tracker's issue type, if the
   adapter exposes one → write `story_points` there directly.
2. Else, a field literally named **Estimation** (or the tracker's closest
   equivalent custom field), if one exists on the project.
3. Else, fall back to a plain `SP: N` line inside `description` — no
   custom field required, works on any tracker.

**Link-type fallback:** `"depends"` and `"parent"` are native issue-link
types on most trackers. If the resolved tracker's adapter has no native
`"depends"` (or equivalent "is required for") link type, degrade to a
plain textual note in the dependent task's `description` (e.g. "Depends
on: `<TASK-ID>`") and log that the degradation happened — never silently
drop a dependency because the tracker lacks a first-class link for it. The
same rule covers `"parent"`: no native parent/sub-issue relation (GitHub
Issues without sub-issues, a Jira project where the parent is a field the
tool cannot set) → a `Parent: <EPIC-ID>` line in the task's description,
logged.

### Illustrative YouTrack adapter

YouTrack is the first supported adapter — shown here as a worked example
of how a concrete tracker satisfies the generic contract in §1, not as
part of the contract itself. Exact MCP tool names are resolved at runtime
via ToolSearch (§3) and vary by server build; the shapes below are
illustrative only.

| Generic call | YouTrack shape (example) |
|---|---|
| `create_issue(summary, description, estimate?, parent?)` | An issue-create MCP tool with `project`, `summary`, `description`; `estimate` written to a project's **Estimation** field if configured, else the `SP: N` description fallback. |
| `link(from, to, "depends")` | YouTrack's native "depends on" / "is required for" issue-link command. |
| `link(from, to, "parent")` | YouTrack's native "subtask of" / epic-link command. |
| `read_issue(<TASK-ID>)` | An issue-read MCP tool, or REST `GET /api/issues/{id}?fields=idReadable,summary,description,links(direction,linkType(name),issues(idReadable)),customFields(name,value(name))` — links and the Estimation field come back in the same read. |
| `search_issues(query)` | YouTrack's own query language through an issue-search tool: `project: <KEY> #Unresolved summary: <words>`; the dry-run shows at most three hits per task. |
| `markup` | `markdown` — YouTrack renders Markdown natively; nothing to convert. |

## 8. Partial-failure handling

If a `create_issue` or `link` call fails partway through a real (non-dry)
run — a missing "depends" link type the adapter didn't actually support, a
rate limit, a network blip — Phase 7 **stops immediately**, does not
retry blindly, and reports:

```
created 4 / remaining 3
  T1 -> <TASK-ID>
  T2 -> <TASK-ID>
  T3 -> <TASK-ID>
  T4 -> <TASK-ID>
  (failed on T5: <error>)
```

listing the `<TASK-ID>`s already created so far by their draft position
(`T1`, `T2`, ...), and naming which task the failure happened on and why.
Never leave the user guessing whether partial writes landed — "created X
/ remaining Y" is the minimum shape of that report, always with the
concrete ids already made, not just the counts.

Because every created issue already carries the stable `decompose-id:...`
key (§6), simply re-running Phase 7 after fixing the underlying problem
(granting the missing link type, waiting out the rate limit) is safe and
idempotent: the first 4 tasks are found by key and left alone (or
updated in place if their draft content changed), and only the remaining
3 get created. The user never has to manually diff the tracker against
the draft to find the orphaned subset.

A **read-back mismatch** (§9 step 7) is reported in the same place, per field:

```
read-back: 6 match / 1 mismatch
  T4 -> <TASK-ID>: estimate sent 5, read back (empty) — field not on this issue type?
```

It is a partial failure even though every `create_issue` returned `ok`: the
tracker accepted the write and then dropped part of it (a workflow rule, a
required field, a permission). Fix the cause and re-run — the idempotency key
finds the issue and updates it in place.

## 9. Procedure Phase 7 runs, in order

1. Confirm §2's two preconditions are both met; if not, stop and ask
   for whichever is missing.
2. Run §3's discovery. If it lands on §4 (no tracker), stop there —
   done, gracefully.
3. **Preflight — one read before any promise.** One read of the target
   project (or the parent epic) proves the token and the project id; what the
   plan may promise comes from `describe_project` when the adapter has it —
   the issue types, the fields and their *types* (a period-typed Estimation
   field takes a duration, not a number: SP go to the description rung), the
   link types. What cannot be read is not promised: a dry-run that offers an
   estimate rung or a link type this project does not have is a plan that
   cannot execute, so drop to §7's fallback rung *now* and say so in the
   dry-run, not after the first write fails. Write permission is proven only
   by a write — which is why step 6 reads the first issue back before creating
   the rest.
4. Render the full create/link plan (every summary, description,
   estimate + which fallback rung, link, and idempotency key) and print
   it as a **dry-run** (§5). Do not write anything yet.
5. Ask the user to confirm the dry-run plan looks right. On rejection,
   stop and let the user revise the draft (back to Phase 6), not this
   file's concern to fix content.
6. On confirmation, re-run the same plan with writes enabled: for each
   task, look up its `decompose-id:...` key first (§6) — update in place
   if found, `create_issue` if not — then issue its `parent` link and any
   `depends` links. Each issue's description carries the draft it came from:
   `Source: <path to the draft>, epic <ID or none>` (§7). Read the **first**
   created issue back before creating the second: a dropped field or a
   missing permission shows up on issue one, not on issue twelve. Draft ids
   (`T1`, `T4`) that a
   description mentions — in `context`, in a `Not in this task:` line, in a
   textual `Depends on:` fallback — are rewritten to the tracker's ids once
   every issue exists: a second, update-only pass, read back like the first.
7. **Read back what you wrote.** After the last create/link, `read_issue`
   every id this run touched and compare the fields you sent: `summary`
   equal; `description` contains the key line, the `Source:` line and, on
   rung 3, the `SP: N` line (not byte for byte — trackers normalise markup);
   `estimate` numerically equal on rungs 1–2; `parent` equal; `links` the set
   of (type, id) pairs the plan issued, a degraded one by its `Depends on:` /
   `Parent:` line. Anything that differs, or an id that reads back empty, is a
   **partial failure** reported per §8 with the exact field: "created, but the
   estimate did not stick" is a state a human can act on; "ok" is not. A
   tracker that silently drops a field (a workflow rule, a required field, a
   permission) is exactly what this step exists to catch. A match is **shown,
   not declared**: the report lists, per issue and per field, the value sent
   and the value read (`estimate: sent 5 / read 5`); the `create_issue`
   response is not a read-back — the read is a separate call after the last
   write. A field the adapter cannot read (`links` on a tool that does not
   return them) is reported as `unverifiable`, never as a match.
8. On any failure mid-way, stop and report per §8 — step 7 still runs over
   every id touched so far. Do not continue creating later tasks past a
   failed one, since later `depends_on` entries may reference the task that
   just failed to create.
9. On full success, return per §10.

## 10. Return

Phase 7 hands back the list of created/updated `<TASK-ID>`s **with their
URLs** (an id alone makes the user search for it), one per draft task,
ready to be fed straight into `task-flow:task` — that skill takes it from
there (ingest → design-spec → premortems → TDD →
review → verify → close). `decompose` and its Phase 7 stop the instant a
well-formed set of tracker issues exists; running any of them is not this
file's or this skill's job.
