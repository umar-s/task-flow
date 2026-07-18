# `task-flow:decompose` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. When authoring the SKILL/reference files, also consult superpowers:writing-skills.

**Goal:** Add a third skill `decompose` to the `task-flow` plugin that turns a large unit of work (free description / existing epic BA-NNN / spec doc) into well-formed, dependency-linked tasks (Name · Context · Requirements · DoD · Story Points · depends_on), reviewed as an MD draft, then pushed to YouTrack as an epic + subtasks.

**Architecture:** A markdown SKILL.md drives a 7-phase flow (ingest → requirements → decompose → enrich → graph/waves → independent QA subagent → draft → YouTrack sync). Heavy reference material (splitting techniques, edge-probe, thinking-models, task schema, QA checklist, draft template, YouTrack sync) lives in `skills/decompose/references/*.md`, addressed via `${CLAUDE_PLUGIN_ROOT}`. Decomposition logic is adapted from the MIT-licensed `@opengsd/gsd-core` (attribution in NOTICE). The skill is trigger-agnostic and stops before execution — each produced BA-NNN is then run through `task-flow:task`.

**Tech Stack:** Markdown skill files (Claude Code plugin format), JSON plugin manifest, YouTrack via MCP (discovered at runtime), Mermaid for the dependency graph in the draft. No compiled code.

## Global Constraints

- Plugin author identity: `Sergei <sergei.bitsmedia@gmail.com>` (matches existing `plugin.json` and marketplace records).
- Co-Authored-By trailer: **do NOT add** (user's rule, same as in `task` discipline).
- Portable asset paths: reference files addressed via `${CLAUDE_PLUGIN_ROOT}/skills/decompose/references/...` — never `~/.claude/...`. **The SKILL resolves this base path at runtime (bash) and Reads references by the resolved absolute path — do NOT assume the literal `${CLAUDE_PLUGIN_ROOT}` string works inside the Read tool** (H-001).
- Canonical task fields — **6 author fields**: `name`, `context`, `requirements`, `dod`, `story_points`, `depends_on`. Plus `truths` (goal-backward observable facts) **nested inside `dod`**, and `wave` (computed from the graph, not an author field). Every consumer (schema / qa / draft / tracker-sync / SKILL) uses these exact names (H-002).
- Estimation unit: **Story Points, Fibonacci `1/2/3/5/8/13`** — an **optional annotation, NOT a gate**. Splitting is driven by SPIDR / vertical slices / dependencies, never by SP. SP > 8 is a WARNING to reconsider, not a hard re-split trigger (H-004).
- Hierarchy depth: **Epic → tasks + per-task `depends_on` graph + waves**. No milestones/roadmap/phases.
- Output contract: the **MD draft is the self-contained primary artifact** (`docs/decompose/YYYY-MM-DD-<epic>.md`). Tracker push is an **optional generic adapter**, runs only after explicit user approval; if no tracker is configured, stop gracefully at the draft (H-005).
- Tracker-agnostic: use a generic `<TASK-ID>` placeholder in contracts/examples — never hardcode `BA-NNN`. YouTrack is the first supported adapter (an example), not the contract (H-005).
- License hygiene: GSD is MIT — material is **adapted (reworded), not copy-pasted**; `NOTICE.md` credits Open GSD. Keep everything generic/depersonalized (public marketplace).
- Skill discipline style must match existing `task`/`ci-gate`: "discipline fixed, concrete commands project-specific", resolve project bindings from `CLAUDE.md`, one todo per phase.
- Version bump: `1.1.0 → 1.2.0`.

## Source material (adapt from — MIT, reword don't copy)

Local GSD cache root `G = /home/serpens/.npm/_npx/a78857a30883db8e/node_modules/@opengsd/gsd-core`:
- `G/agents/gsd-planner.md` — break_into_tasks, task anatomy, scope-reduction prohibition
- `G/gsd-core/references/spidr-splitting.md` — SPIDR axes + anti-patterns
- `G/gsd-core/references/edge-probe.md` — 8 edge categories
- `G/gsd-core/references/thinking-models-planning.md` — pre-mortem/MECE/constraint/curse-of-knowledge
- `G/gsd-core/references/questioning.md` — dream-extraction questioning
- `G/agents/gsd-plan-checker.md` — QA dimensions
- `G/gsd-core/templates/phase-prompt.md` + `roadmap.md` + `requirements.md` — field shapes

## File Structure

Repo `task-flow` (fresh clone of `umar-s/task-flow`):

- Create `skills/decompose/SKILL.md` — the 7-phase flow (body). Single responsibility: orchestrate decomposition; delegate detail to references.
- Create `skills/decompose/NOTICE.md` — MIT attribution to Open GSD.
- Create `skills/decompose/references/splitting.md` — SPIDR (5 axes) + plan-split signals.
- Create `skills/decompose/references/edge-probe.md` — 8 edge categories + relevance filter.
- Create `skills/decompose/references/thinking-models.md` — pre-mortem, MECE, constraint-first, curse-of-knowledge; "when NOT to think".
- Create `skills/decompose/references/task-schema.md` — the 6 fields + goal-backward truths + one worked example.
- Create `skills/decompose/references/qa-checklist.md` — the independent plan-checker subagent brief + 7-point checklist.
- Create `skills/decompose/references/draft-template.md` — the `docs/decompose/*.md` layout.
- Create `skills/decompose/references/tracker-sync.md` — **generic tracker adapter**: MCP tool discovery + field/link mapping + fallbacks + dry-run + partial-failure handling + stable idempotency key. YouTrack = first supported adapter.
- Modify `.claude-plugin/plugin.json` — version, description, keywords.
- Modify `README.md`, `README.ru.md` — add decompose row + pipeline diagram.
- Create `docs/superpowers/specs/2026-07-18-task-flow-decompose-design.md` — copy of approved spec.
- Create `docs/superpowers/plans/2026-07-18-decompose-skill.md` — copy of this plan.

Marketplace repo `devpowers` (separate): `README.md` catalog note (marketplace.json untouched — source pinned to `main`).

---

### Task 0: Working clone + skill skeleton

**Files:**
- Create: `docs/superpowers/specs/2026-07-18-task-flow-decompose-design.md`
- Create: `docs/superpowers/plans/2026-07-18-decompose-skill.md`
- Create: `skills/decompose/` (dir)

- [ ] **Step 1: Fresh clone into working dir**

```bash
cd /tmp/claude-1000/-home-serpens/b1a7c37e-e071-448c-8870-7a28c6a6fb59/scratchpad
rm -rf task-flow-work && git clone https://github.com/umar-s/task-flow.git task-flow-work
cd task-flow-work && git checkout -b feat/decompose-skill
```

- [ ] **Step 2: Copy approved spec + this plan into repo**

```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans skills/decompose/references
cp ../2026-07-18-task-flow-decompose-design.md docs/superpowers/specs/
cp ../2026-07-18-decompose-skill-plan.md docs/superpowers/plans/2026-07-18-decompose-skill.md
```

- [ ] **Step 3: Verify structure**

Run: `ls skills/decompose/references && ls docs/superpowers/{specs,plans}`
Expected: references dir exists (empty), both docs present.

- [ ] **Step 4: Commit**

```bash
git add docs skills/decompose
git commit -m "decompose: scaffold skill dir + spec/plan docs"
```

---

### Task 1: NOTICE + splitting reference

**Files:**
- Create: `skills/decompose/NOTICE.md`
- Create: `skills/decompose/references/splitting.md`

**Interfaces:**
- Produces: `splitting.md` referenced by SKILL Phase 2 as `${CLAUDE_PLUGIN_ROOT}/skills/decompose/references/splitting.md`.

- [ ] **Step 1: Write NOTICE.md**

Content: state that decomposition logic is adapted from `@opengsd/gsd-core` (Open GSD, MIT, © 2026), reworded and restructured; this plugin is MIT; no GSD source copied verbatim.

- [ ] **Step 2: Write splitting.md** — adapt from `G/gsd-core/references/spidr-splitting.md` (reword). Must contain:
  - When to split (triggers): compound "and" capabilities, multi-actor, oversized, vague noun-phrase capability.
  - **SPIDR — one axis per split**, each with a probe question and ordering rule:
    - Spike (unknown → research task, no acceptance beyond "we know enough to plan the rest")
    - Paths (happy path first, edge paths as follow-ups)
    - Interfaces (web/API/CLI/mobile — user-facing first)
    - Data (smallest scope first)
    - Rules (minimum viable rules first)
  - Anti-patterns: **no horizontal/technical-layer splits** ("schema phase → API phase → UI phase" — reject), no pre-splitting, one axis at a time.
  - Task-level split signals (adapt from planner `<scope_estimation>`): SP > 8, >5 files, multiple subsystems, checkpoint + impl mixed → split.

- [ ] **Step 3: Verify no verbatim copy**

Run: `python3 -c "import difflib,sys; a=open('skills/decompose/references/splitting.md').read(); b=open('$G/gsd-core/references/spidr-splitting.md').read(); print('longest common block chars:', max((len(x) for x in [a[m.a:m.a+m.size] for m in difflib.SequenceMatcher(None,a,b).get_matching_blocks()]), default=0))"`
Expected: longest common block < 120 chars (i.e. no sentence-length verbatim lifts). If ≥120, reword the offending passage.

- [ ] **Step 4: Commit**

```bash
git add skills/decompose/NOTICE.md skills/decompose/references/splitting.md
git commit -m "decompose: NOTICE + splitting reference (SPIDR, adapted)"
```

---

### Task 2: edge-probe reference

**Files:**
- Create: `skills/decompose/references/edge-probe.md`

**Interfaces:**
- Produces: `edge-probe.md` referenced by SKILL Phase 0/1.

- [ ] **Step 1: Write edge-probe.md** — adapt from `G/gsd-core/references/edge-probe.md`. Must contain:
  - Purpose: surface edge cases at spec time so DoD assertions exist (unwritten requirement → unchecked behavior).
  - **Relevance filter first** — classify each requirement (numeric-range / collection / text / stateful / io), then raise only relevant categories.
  - The 8 categories, each with a probe question: boundary, adjacency, empty/degenerate, encoding, ordering/stability, precision/overflow, idempotency, concurrency.
  - Dismissal requires a reason string (silence is invalid); resolved edge → becomes a DoD acceptance criterion.

- [ ] **Step 2: Verify no verbatim copy** (same difflib check as Task 1, against `edge-probe.md`). Expected < 120 chars.

- [ ] **Step 3: Commit**

```bash
git add skills/decompose/references/edge-probe.md
git commit -m "decompose: edge-probe reference (8 categories, adapted)"
```

---

### Task 3: thinking-models reference

**Files:**
- Create: `skills/decompose/references/thinking-models.md`

- [ ] **Step 1: Write thinking-models.md** — adapt from `G/gsd-core/references/thinking-models-planning.md`. Must contain, each with the failure mode it counters:
  - Pre-mortem ("assume it failed; list 3 likely reasons; add mitigation/acceptance").
  - MECE at requirement level (every requirement maps to exactly one task's DoD; two tasks on same file must serve different requirements).
  - Constraint-first (hardest constraint scheduled as task 1–2, spike it if external/unfamiliar).
  - Curse-of-knowledge counter (re-read each task as if codebase unknown; every noun/verb unambiguous).
  - **When NOT to think**: single-task cuts, well-understood/boilerplate work — skip the models.

- [ ] **Step 2: Verify no verbatim copy** (difflib vs `thinking-models-planning.md`, < 120 chars).

- [ ] **Step 3: Commit**

```bash
git add skills/decompose/references/thinking-models.md
git commit -m "decompose: thinking-models reference (adapted)"
```

---

### Task 4: task-schema reference

**Files:**
- Create: `skills/decompose/references/task-schema.md`

**Interfaces:**
- Produces: the canonical task field set consumed by Phase 3 (enrich), the QA checklist (Task 5), the draft template (Task 6), and tracker sync (Task 7). **Canonical names, used verbatim by every consumer:** the **6 author fields** `name`, `context`, `requirements`, `dod`, `story_points`, `depends_on`; plus `truths` (goal-backward observable facts) **nested inside `dod` alongside `done`/`acceptance_criteria`/`verify`**; plus `wave` (computed from the graph in Phase 4, not authored). Document this "6 + truths-in-dod + computed wave" canon explicitly so no consumer says "6 fields" while another says "8".

- [ ] **Step 1: Write task-schema.md** with the exact field table (from spec §6), an explicit statement of the canon above, and one fully worked example task (all fields filled, realistic values, SP=3, depends_on non-empty, `dod` containing `truths`).

Worked example skeleton (fill with a concrete auth-login task):

```markdown
### T3: Implement POST /login endpoint
- **context:** why + @refs to model/convention files + related tasks
- **requirements:** [REQ-02]
- **dod:**
  - done: valid creds → 200 + JWT cookie; invalid → 401
  - acceptance_criteria: route file contains "maxAge: 900"; returns Set-Cookie
  - verify: `pnpm test auth/login.test.ts` passes (<60s)
- **truths:** ["User can log in with email+password", "Wrong password is rejected"]
- **story_points:** 3
- **depends_on:** [T1]     # T1 = User model
- **wave:** 2
```

- [ ] **Step 2: Verify field-name consistency**

Run: `grep -oE "story_points|depends_on|acceptance_criteria|truths|context|requirements|\bwave\b|\bname\b|\bdod\b" skills/decompose/references/task-schema.md | sort -u`
Expected: all canonical names present, spelled exactly. These are the names every downstream file reuses (enforced mechanically in Task 10).

- [ ] **Step 3: Commit**

```bash
git add skills/decompose/references/task-schema.md
git commit -m "decompose: task-schema reference (6 fields + worked example)"
```

---

### Task 5: QA checklist (independent subagent)

**Files:**
- Create: `skills/decompose/references/qa-checklist.md`

**Interfaces:**
- Consumes: field names from `task-schema.md` (Task 4).
- Produces: the subagent brief invoked by SKILL Phase 5 (via the Agent tool, fresh context).

- [ ] **Step 1: Write qa-checklist.md** — adapt from `G/agents/gsd-plan-checker.md`. Must contain:
  - **Adversarial stance**: assume the breakdown is flawed until proven otherwise; every finding carries severity (BLOCKER/WARNING).
  - The 7 checks (from spec §7): (1) requirement coverage — every `REQ-NN` in ≥1 task (BLOCKER); (2) **field completeness — all 6 author fields present, and `dod` contains `truths`; `wave` present** (missing author field or missing `truths` → BLOCKER); (3) graph acyclicity — no cycles / dangling / forward refs / wave-consistency (BLOCKER); (4) **atomicity — each task is a vertical slice, single concern, independently testable; `story_points` > 8 → WARNING "reconsider splitting", NOT a hard re-split driver** (H-004); (5) key-links — artifacts wired, not isolated; (6) no silent scope reduction — marker scan (BLOCKER); (7) MECE — no two tasks per requirement without a clear split.
  - Output format: `PASSED` or `ISSUES FOUND` + YAML list `{task, check, severity, description, fix_hint}`.
  - Revision loop cap: ≤ 3 cycles, then escalate to user.

- [ ] **Step 2: Verify checks reference real field names**

Run: `grep -c -E "story_points|depends_on|requirements|truths|wave" skills/decompose/references/qa-checklist.md`
Expected: ≥ 4 (checklist actually inspects the schema fields incl. `truths`/`wave`, not vague prose).

- [ ] **Step 3: Commit**

```bash
git add skills/decompose/references/qa-checklist.md
git commit -m "decompose: QA checklist for independent plan-checker subagent"
```

---

### Task 6: draft template

**Files:**
- Create: `skills/decompose/references/draft-template.md`

**Interfaces:**
- Consumes: field names from `task-schema.md`.
- Produces: the exact `docs/decompose/YYYY-MM-DD-<epic>.md` layout written by Phase 6.

- [ ] **Step 1: Write draft-template.md** containing a literal fill-in template:
  - Epic header: title, goal, SP rollup (sum), wave count.
  - Task table: `| ID | Name | SP | depends_on | wave | REQ |`.
  - Per-task cards — all 6 author fields; `dod` block shows its nested `truths`.
  - Mermaid `graph TD` dependency diagram block.
  - Traceability table: `| REQ | Tasks |`.

- [ ] **Step 2: Verify mermaid + table present**

Run: `grep -E "mermaid|graph TD|\| ID \|" skills/decompose/references/draft-template.md`
Expected: mermaid fence and the task-table header line both present.

- [ ] **Step 3: Commit**

```bash
git add skills/decompose/references/draft-template.md
git commit -m "decompose: MD draft template (table + cards + mermaid graph)"
```

---

### Task 7: Tracker sync reference (generic adapter)

**Files:**
- Create: `skills/decompose/references/tracker-sync.md`

**Interfaces:**
- Consumes: field names from `task-schema.md`.
- Produces: the runtime procedure Phase 7 follows to push tasks to a tracker.

- [ ] **Step 1: Write tracker-sync.md**. Must contain:
  - **Adapter model** (H-005): a generic contract — `create_issue(summary, description, estimate?, parent?)`, `link(from, to, type)` — with YouTrack as the **first supported adapter**. The MD draft is the primary artifact; the tracker push is optional.
  - **No-tracker graceful stop** (H-005): if no tracker MCP is discoverable and `CLAUDE.md` defines no tracker binding, **stop at the draft** and tell the user the draft is the deliverable — do NOT error out. Use a generic `<TASK-ID>` placeholder everywhere; never hardcode `BA-NNN` (YouTrack ids are shown only as an example).
  - **Runtime tool discovery** (tracker MCP is only present in project sessions): locate tracker MCP tools via ToolSearch (e.g. "youtrack create issue / issue command / link"), resolve tracker specifics from `CLAUDE.md` bindings, exactly like `task` does.
  - **Preconditions**: never push without prior user approval of the draft; require target project/parent-epic id.
  - **Dry-run mode** (H-003): support a dry-run that **prints the full create/link plan** (every issue summary, description, estimate, and link) **without writing** — this is both the safety default for a production tracker and the acceptance-test path (Task 11).
  - **Stable idempotency key** (H-003): stamp each created issue with a marker `decompose-id:<draft-slug>#<n>` (in a custom field or the description); on re-run, match by that key, **not by summary string**. Same key → update; missing key → create. Prevents duplicate sets when the LLM regenerates slightly different summaries.
  - **Partial-failure handling** (H-003): if a create/link fails midway (missing "depends" link type, rate-limit, network), stop, report `created X / remaining Y` with the ids already made, and make the re-run idempotent via the stable key — never leave the user guessing about orphans.
  - **Field mapping**: `name`→summary; `context`+`requirements`+`dod` (incl. `truths`)→markdown description; `story_points`→estimate field if it exists, else Estimation field, else a `SP: N` line in description (fallback ladder, log which was used); `depends_on`→native "depends"/"is required for" links; epic membership→parent/"subtask of" link.
  - **Return**: list of created/updated `<TASK-ID>`s ready for `task-flow:task`.

- [ ] **Step 2: Verify adapter contract + safety rails documented**

Run: `grep -E "dry-run|decompose-id|approval|no tracker|created X|Estimation|ToolSearch|<TASK-ID>" skills/decompose/references/tracker-sync.md`
Expected: dry-run, stable key, approval gate, no-tracker stop, partial-failure line, estimation fallback, tool discovery, and the generic id placeholder all present.

- [ ] **Step 3: Verify no hardcoded private tracker id**

Run: `grep -n "BA-[0-9]" skills/decompose/references/tracker-sync.md && echo "LEAK" || echo "no BA-NNN hardcode"`
Expected: `no BA-NNN hardcode` (private prefix must not appear as a contract).

- [ ] **Step 4: Commit**

```bash
git add skills/decompose/references/tracker-sync.md
git commit -m "decompose: generic tracker-sync reference (dry-run, stable key, partial-failure, no-tracker stop)"
```

---

### Task 8: SKILL.md body (the 7-phase flow)

**Files:**
- Create: `skills/decompose/SKILL.md`

**Interfaces:**
- Consumes: all seven reference files (`splitting`, `edge-probe`, `thinking-models`, `task-schema`, `qa-checklist`, `draft-template`, `tracker-sync`).
- Produces: the skill entrypoint (frontmatter `name: decompose` + trigger description).

- [ ] **Step 1: Write frontmatter** — match `task`/`ci-gate` style. `name: decompose`; description covers triggers: "/decompose", "нарежь на задачи", "декомпозируй эпик/фичу", "разбей проект на задачи", plus what it does (epic/feature/spec → tasks with DoD/SP/deps → MD draft → optional tracker) and that it runs **before** `task`.

- [ ] **Step 2: Write body** — same discipline framing as `task` ("discipline fixed; concrete commands project-specific — read CLAUDE.md"). One todo per phase. Sections:
  - **Reference loading** (H-001): first resolve the skill base dir at runtime — `ROOT="${CLAUDE_PLUGIN_ROOT:-<dir of this SKILL.md>}"` via a bash step — then `Read "$ROOT/skills/decompose/references/<file>.md"` by the **resolved absolute path**. Never pass the literal `${CLAUDE_PLUGIN_ROOT}` string to the Read tool. Load each reference lazily, only in the phase that needs it (progressive disclosure).
  - **Project bindings** (resolve from CLAUDE.md): tracker create-issue/link/fields (optional); where drafts live (`docs/decompose/`).
  - **Input**: accept free description | existing tracker id `<TASK-ID>` | spec path (auto-detect). Never assume a specific id prefix.
  - **Phase 0 Ingest & scope** → read project context; if requirements missing, extract via dream-extraction + `edge-probe.md`.
  - **Phase 1 Requirements** → `REQ-NN` list + traceability.
  - **Phase 2 Decompose** → dependency-first (needs/creates), vertical slices, apply `splitting.md` + `thinking-models.md`, scope-reduction prohibition. **Splitting is driven by SPIDR/slices/deps, never by SP** (H-004).
  - **Phase 3 Enrich** → fill the 6 author fields per `task-schema.md`; `dod` includes goal-backward `truths`; `story_points` is an optional annotation.
  - **Phase 4 Graph & waves** → build `depends_on` graph, check acyclic, compute `wave`s, SP rollup (informational).
  - **Phase 5 QA** → dispatch independent subagent with `qa-checklist.md` (fresh context, Agent tool); revise ≤3 cycles on BLOCKER.
  - **Phase 6 Draft** → write draft per `draft-template.md` (**self-contained primary artifact**); **stop, get user approval**.
  - **Phase 7 Tracker sync (optional)** → on approval, follow `tracker-sync.md` — default to **dry-run** (print plan), then real push; if no tracker configured, stop at draft; return `<TASK-ID>` list.
  - **Handoff**: each produced `<TASK-ID>` → run `task-flow:task`.

- [ ] **Step 3: Verify all reference links resolve + base-path pattern present**

Run: `for f in $(grep -oE 'references/[a-z-]+\.md' skills/decompose/SKILL.md | sed 's|references/||' | sort -u); do test -f skills/decompose/references/$f && echo "OK $f" || echo "MISSING $f"; done; grep -q 'CLAUDE_PLUGIN_ROOT:-' skills/decompose/SKILL.md && echo "base-path resolve OK" || echo "MISSING base-path resolve"`
Expected: every referenced file prints `OK`, and `base-path resolve OK` (the runtime resolution from H-001 is present).

- [ ] **Step 4: Verify frontmatter validity**

Run: `python3 -c "import yaml,sys; t=open('skills/decompose/SKILL.md').read(); fm=t.split('---')[1]; d=yaml.safe_load(fm); assert d['name']=='decompose' and d.get('description'); print('frontmatter OK:', list(d.keys()))"`
Expected: `frontmatter OK: ['name', 'description']`.

- [ ] **Step 5: Commit**

```bash
git add skills/decompose/SKILL.md
git commit -m "decompose: SKILL.md — 7-phase decomposition flow"
```

---

### Task 9: Manifest + README

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `README.md`, `README.ru.md`

- [ ] **Step 1: Bump manifest**

In `.claude-plugin/plugin.json`: `version` → `"1.2.0"`; append to `description` " + a decompose skill that slices an epic/feature/spec into dependency-linked tasks (DoD, Story Points, graph) and pushes them to the tracker."; add keywords `"decomposition"`, `"planning"`, `"story-points"`, `"youtrack"`.

- [ ] **Step 2: Verify JSON valid + version**

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); assert d['version']=='1.2.0'; assert 'decompose' in d['description']; print('manifest OK')"`
Expected: `manifest OK`.

- [ ] **Step 3: Update READMEs** — add `decompose` to the skills table in both `README.md` and `README.ru.md`, add it to the install/usage note, and add a one-line pipeline diagram `decompose → task → ci-gate`.

- [ ] **Step 4: Verify both READMEs mention decompose**

Run: `grep -c decompose README.md README.ru.md`
Expected: each ≥ 2.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json README.md README.ru.md
git commit -m "decompose: bump plugin to 1.2.0 + document in READMEs"
```

---

### Task 10: Structural validation (whole skill)

**Files:** none (validation only).

- [ ] **Step 1: Full asset-path + license sweep**

```bash
# every ${CLAUDE_PLUGIN_ROOT} path exists
grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9/_.-]+' skills/decompose/SKILL.md \
  | sed 's|${CLAUDE_PLUGIN_ROOT}/||' | sort -u \
  | while read p; do test -e "$p" && echo "OK $p" || echo "MISSING $p"; done
# no hardcoded home paths leaked
grep -rn "/home/serpens\|~/.claude" skills/decompose && echo "LEAK FOUND" || echo "no home-path leaks"
```
Expected: all `OK`, and `no home-path leaks`.

- [ ] **Step 2: Cross-consumer field-name coverage (H-002)**

The single defense against silent schema drift: every canonical field name must appear in every file that consumes it.

```bash
# 6 author fields must appear in qa-checklist, draft-template, and SKILL
for name in name context requirements dod story_points depends_on; do
  for f in references/qa-checklist references/draft-template SKILL; do
    grep -q "$name" skills/decompose/$f.md || echo "MISSING author-field '$name' in $f"
  done
done
# truths + wave must appear in schema, qa-checklist, draft-template (they are enforced/rendered there)
for name in truths wave; do
  for f in references/task-schema references/qa-checklist references/draft-template; do
    grep -q "$name" skills/decompose/$f.md || echo "MISSING '$name' in $f"
  done
done
echo "field-coverage check done"
```
Expected: no `MISSING …` lines before `field-coverage check done`. Any MISSING = a consumer lost a field → fix before proceeding.

- [ ] **Step 3: No-verbatim-GSD final check across all references**

Run the simple per-file difflib check from Tasks 1–3 once more for `splitting`, `edge-probe`, `thinking-models` against their GSD sources (`spidr-splitting.md`, `edge-probe.md`, `thinking-models-planning.md` under `$G/gsd-core/references/`).
Expected: each longest-common block < 120 chars.

- [ ] **Step 4: Commit (if any fixes were needed)**

```bash
git add -A && git commit -m "decompose: fix asset paths / field-coverage / reword verbatim passages" || echo "nothing to fix"
```

---

### Task 11: Acceptance run on a real epic (in the Bits.ai session)

**Files:** none (produces a throwaway draft, not committed).

> Run this in the **Bits.ai project session** (it has the YouTrack MCP the user designated for testing). This is the functional test — "run it and see it work". **No real writes to the production tracker** — Phase 7 is exercised in dry-run only.

- [ ] **Step 1: Load the skill as a PLUGIN pointing at the working clone (H-001)**

Install decompose **as a plugin from the working clone** (e.g. `/plugin marketplace add <clone-path>` then install, or the local dev-plugin mechanism) so `${CLAUDE_PLUGIN_ROOT}` is defined. **Do NOT copy into `~/.claude/skills/`** — a personal skill has no `CLAUDE_PLUGIN_ROOT`, so references would not load and the test would falsely pass. Restart the session so the skill registers.

- [ ] **Step 2: Pre-check — references actually load via the plugin path (H-001)**

Before decomposing, confirm the base-path resolution works: have the skill (or a manual check) resolve `$CLAUDE_PLUGIN_ROOT` and Read one reference (e.g. `qa-checklist.md`); confirm non-empty, real content is loaded into context.
Expected: reference content appears. If empty/failed → fix the Task 8 reference-loading pattern before continuing (this is the exact failure H-001 warns about).

- [ ] **Step 3: Decompose a real epic to DRAFT (no real push)**

Pick a real epic (candidate: DEV-540, or a Bits.ai feature). Invoke `/decompose <epic-or-description>`. Run Phases 0–6, **stop at the draft** — do not approve a real tracker push.

- [ ] **Step 4: Exercise Phase 7 in DRY-RUN (H-003)**

Approve only the **dry-run**: let Phase 7 print the full create/link plan (every issue summary, description, estimate, stable `decompose-id` key, and links) **without writing** to the tracker. Verify the plan is well-formed: parent/subtask links present, `depends_on` mapped to link edges, estimate-field fallback chosen and logged, each issue carries a stable key. **Do not run the real write against the production Bits.ai tracker.**

- [ ] **Step 5: Verify against spec §12 success criteria**

Check the produced `docs/decompose/*.md` and the dry-run plan:
- Every `REQ-NN` appears in ≥1 task (traceability table has no empty rows).
- Every task has all 6 author fields populated, and `dod` includes `truths`.
- Dependency graph is acyclic (mermaid renders; no task depends on a later-wave task).
- `story_points` present as annotation; any SP > 8 carries a "reconsider" note (WARNING, not a failure).
- The QA subagent (Phase 5) reported `PASSED` (or all BLOCKERs were resolved).
- The Phase 7 dry-run plan is well-formed (Step 4).

Expected: all hold. If any fail, fix the SKILL/reference wording and re-run.

- [ ] **Step 6: Record the acceptance result**

Note which epic was used and that all criteria held (scratch file or memory). No commit to the repo (draft is throwaway).

---

### Task 12: Publish

**Files:** none new (publish existing commits).

- [ ] **Step 1: Push branch + open PR/merge to main**

```bash
git push -u origin feat/decompose-skill
gh pr create --repo umar-s/task-flow --base main --title "decompose skill (task-flow 1.2.0)" --body "Adds skills/decompose: epic/feature/spec → dependency-linked tasks (DoD, Story Points, graph) → MD draft → optional generic tracker. Adapted from MIT @opengsd/gsd-core (NOTICE). No Co-Authored-By per task discipline."
```
(Or merge directly to `main` if the user prefers no PR — ask.)

- [ ] **Step 2: Verify marketplace resolves 1.2.0**

Run: `gh api repos/umar-s/task-flow/contents/.claude-plugin/plugin.json --jq '.content' | base64 -d | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"`
Expected: `1.2.0` (after merge to main; marketplace source is pinned to `main`).

- [ ] **Step 3: Update this host + record memory**

```bash
claude plugin update task-flow   # then restart session
```
Add a project-memory note: decompose skill added to task-flow 1.2.0, canonical source is the repo, drafts live in `docs/decompose/`, runs before `task`.

- [ ] **Step 4: Optional — devpowers catalog**

If desired, update `umar-s/devpowers/README.md` to mention the new decompose skill under task-flow (marketplace.json needs no change — source pinned to `main`).

---

## Self-Review

**1. Spec coverage:**
- §4 Input (3 forms) → Task 8 Step 2 (Input section). ✓
- §5 Phases 0–7 → Task 8 Step 2 (all phases) + references Tasks 1–7. ✓
- §6 Task schema (6 author fields + `truths`-in-`dod` + computed `wave`) → Task 4. ✓
- §7 QA checklist → Task 5 + Phase 5 dispatch (Task 8). ✓
- §8 Draft format (self-contained primary artifact) → Task 6. ✓
- §9 Tracker sync (generic adapter) → Task 7 + Phase 7. ✓
- §10 Handoff to task → Task 8 (Handoff section). ✓
- §11 Packaging → Task 9 + Task 12. ✓
- §12 Success criteria → Task 11 (acceptance run + Phase 7 dry-run). ✓
- §13.1 Tracker field/link discovery → Task 7 (runtime discovery + fallback ladder). ✓
- §13.2 License → Global Constraints + NOTICE (Task 1) + no-verbatim checks (Tasks 1–3, 10). ✓

**Premortem fixes applied (traceability):**
- H-001 (personal-skill breaks `${CLAUDE_PLUGIN_ROOT}`) → Global Constraints (runtime resolve), Task 8 Step 2 (base-path resolve) + Step 3 (verify), Task 11 Step 1–2 (plugin-only install + reference-load pre-check).
- H-002 (6-vs-8 fields drift) → canon in Global Constraints + Task 4, Task 5 check 2, Task 6, Task 8 Phase 3, **Task 10 Step 2 cross-consumer test**.
- H-003 (untested non-transactional push) → Task 7 (dry-run + stable key + partial-failure), Task 11 Step 4 (dry-run exercise before publish).
- H-004 (SP hard gate) → Global Constraints (SP = optional annotation), Task 5 check 4 (SP>8 → WARNING), Task 8 Phase 2, §12.
- H-005 (YouTrack-only + BA-NNN hardcode) → Global Constraints (generic `<TASK-ID>`, draft primary), Task 7 (generic adapter + no-tracker stop), Task 8 (Input/Phase 7).

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" in tasks; each file has an explicit content spec and a concrete verify command. Reference-file prose is specified by required-contents lists (not full text) because these are adapted-from-source documents — the source file and the exact required elements are named, which is the actionable spec for a skill-authoring task. ✓

**3. Type consistency:** Field names fixed in Task 4 (`name`, `context`, `requirements`, `dod`{`done`,`acceptance_criteria`,`verify`}, `truths`, `story_points`, `depends_on`, `wave`) and reused verbatim in Tasks 5, 6, 7, 8 and their verify greps. ✓

**Note on TDD adaptation:** a skill is a prompt document, not executable code, so "tests" here are (a) structural validations (frontmatter/JSON/path/verbatim checks) after each authored file, and (b) one functional acceptance dry-run on a real epic (Task 11). This substitutes for the red-green cycle where there is no runtime unit to assert on.
