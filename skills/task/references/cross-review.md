# Cross-review — the other model reviews (phases 6 and 6b)

Loaded in phase 6 / 6b when the review goes to the **other harness**. The
brief is unchanged — `code-review-prompt.md` for phase 6,
`security-review-prompt.md` for 6b — and so is its *After the review comes
back* contract. What changes is who reads the brief: a model from the other
vendor, headless, read-only, in a clean context it cannot inherit anything
from.

## 1. Who reviews

- **The reviewer is the harness that did not write the diff.** Author in
  Claude Code → `--by codex`; author in Codex → `--by claude`. A ticket that
  carries `builder: codex | claude` names the author; the reviewer is the
  other one. No model grades its own work.
- **Why it is the first choice:** the independence becomes structural twice —
  a clean context (the dispatch rule) and a different model with its own
  training, tool habits and blind spots. Two models finding the same defect
  independently is the strongest signal this flow produces.
- **"No weaker than the session's" still holds:** pass `--model` when the
  harness default is weaker than the session that wrote the code.
- **Fallback:** the other CLI absent, not logged in, out of quota, or its
  sandbox cannot start → the same-model subagent dispatch of phase 6, said in
  the evidence block (`review @ <sha> (same-model: codex not installed)`).
  A fallback is a recorded decision; a silent one is a skipped step.

## 2. Running it

```bash
git fetch --no-tags origin <integration-branch>          # a stale base reviews the wrong range
bash "$ROOT/templates/xreview/xreview.sh" --by codex --task <TASK-ID> --base origin/<integration-branch>
bash "$ROOT/templates/xreview/xreview.sh" --by codex --task <TASK-ID> --base origin/<integration-branch> --kind security   # 6b
```

| Exit | Meaning | What the orchestrator does |
|---|---|---|
| `0` | the review ran; code: `VERDICT yes`; security: `critical=0 high=0` | read the report anyway — Optional/Medium findings are still findings |
| `1` | the review ran; the verdict blocks | the template's contract: fix, `fix(review): <id>`, re-review the delta |
| `2` | the review **did not happen** or cannot be read | the phase is not passed — fix the cause or fall back (§1), and say which |

What the script does, in order — each step that cannot complete exits `2`:

1. Resolves `merge-base(--head, --base)..--head` and refuses an empty range
   (an empty diff reviews as "no findings").
2. Reads the spec at `docs/specs/<TASK-ID>.spec.md` (`--spec <path>` when the
   project's artifact directory differs) and fills the slots from it: the
   *DoD → check table* section is `[DOD]` (no section → `2`), *Premortem
   edges* is `[PREMORTEM_EDGES]` for phase 6 and is **never** passed to 6b,
   the rest of the spec is `[DESIGN_SPEC]`. `[WHAT_CHANGED]` is the range's
   commit subjects unless `--what-changed <file>` gives the factual summary.
   Insertion is literal and single-pass; nothing from the spec is executed.
3. Runs the reviewer read-only and isolated (below), with the brief on stdin.
   For Claude Code the brief also carries the range material — `git diff
   --stat`, `git log`, `git status --short` and the full diff, run at dispatch
   time (6b leaves out the spec's own diff) — and the checkout must be at the
   head under review, because that reviewer has no shell.
4. Reads the verdict from the **last two non-empty lines** of the answer and
   nothing else: `REVIEWED <sha>` naming the range head, then `VERDICT
   yes|no|with-fixes` (6b: `SUMMARY critical=N high=N medium=N low=N`) — plain
   text, exact shape, nothing after them. Anything else is `2`: an unread
   verdict is never a clean one. Parsing free-form Markdown for a verdict
   failed twice in review (a quoted, commented, indented or fenced verdict
   reads differently to a person and to a parser), so the verdict is a
   separate channel, and the script writes it into the report header itself:
   the reader sees the verdict the runner used.
5. Writes `docs/reviews/<TASK-ID>-<sha7>-<by>[-security].md` (header by the
   script: reviewer, model, range, brief hash, isolation, `reviewed` sha,
   verdict; body by the reviewer, its machine lines moved into the header and
   any look-alike header row escaped) and prints its path. Phase 8 takes the
   sha from that `reviewed` row; the exit code, not a grep of the file, is
   the verdict a runner acts on.

**Read-only, by construction:**

| Reviewer | How |
|---|---|
| Codex | `codex exec -s read-only --ignore-rules --ephemeral` — the sandbox refuses writes and network for every command the model runs; `--ignore-rules` because an execpolicy `allow` (user or project `.rules`) runs the matched command outside the sandbox (observed 2026-10-16) |
| Claude Code | `claude -p --tools Read,Grep,Glob --permission-mode dontAsk --strict-mcp-config --disable-slash-commands --setting-sources "" --settings '{"disableAllHooks":true}'` — no shell (an allowlisted `git diff --output=<file>` writes, and git accepts abbreviated long options, so the range material is attached instead), no MCP server (`--tools` limits only the built-in set), no skills, and no settings file: the diff under review can commit a `.claude/settings.json` or `settings.local.json` whose hooks and `apiKeyHelper` command run when the reviewer starts (both observed 2026-10-16; the same hook in `.codex/hooks.json` did not run under `--ignore-user-config`) |

`XREVIEW_ALLOW='Bash(make test)'` gives the Claude reviewer a shell for
exactly those rules, when it should run the project's test command — a
capability the owner grants: the read-only guarantee then rests on the
command allowed. A diff above `XREVIEW_MAX_DIFF_BYTES` (2 MB) is refused,
not truncated: split the review.

**Isolated from the author's memory, by default.** A reviewer CLI started
normally loads the user's plugins, and memory plugins replay the project's
recent history — the implementation story — at session start. Measured on
2026-10-16: `claude -p` ran 9 SessionStart hooks of user plugins, with the
user's settings left out none; `codex exec` ran 4, with
`--ignore-user-config` none. The project's own instruction file still loads.
`XREVIEW_ISOLATE=0` brings the user's own settings and plugins back — only
with a reason in the evidence block; it never brings back MCP servers,
execpolicy rules, or a settings file from the repository.

**No session identity crosses over.** The reviewer's environment drops the
author session's ids, plugin paths, prediction-protocol variables and the
parent's messaging channel (`CLAUDECODE`, `CLAUDE_CODE_*` session variables,
`CODEX_SESSION_ID`, `PP_SESSION`, `PREDICT`, …): a nested harness otherwise
inherits them.

**Where it runs:**
- From a Claude Code session: a read-only `codex exec` is allowed even in
  auto mode; a write-capable one is refused there — this script never asks
  for one.
- From a Codex session: the default sandbox has no network, and the other
  CLI needs it — approve running the script outside the sandbox, or run it
  from a terminal.
- From a runner: the same command; the runner exports nothing the scrub
  would have to undo.
- Ubuntu 23.10+ with `kernel.apparmor_restrict_unprivileged_userns=1`: the
  Codex sandbox (bwrap) needs an AppArmor profile for the `codex` binary, or
  every reviewer command fails — the script then exits `2` with the
  reviewer's stderr.

## 3. After the report comes back

- The contract in `code-review-prompt.md` (*After the review comes back*)
  applies unchanged: severity → action, the behavioural/description split,
  one `fix(review): <id>` commit per finding, `REVIEWED <sha>`.
- **The delta goes back to the same other model:** `--base <the reviewed sha>`
  reviews exactly what the fixes changed. A delta reviewed by the author's
  model is a same-model review, and is named as one.
- **Committing the report does not move the verdict.** A commit that touches
  only `docs/reviews/` and `docs/evidence/` keeps `REVIEWED <sha>` valid;
  anything else is unreviewed. Check it, do not assume it:

  ```bash
  git diff --quiet <reviewed-sha>..HEAD -- . ':!docs/reviews' ':!docs/evidence'   # rc 0 → the verdict still holds
  ```
- **Interactive Codex, subagent instead of the script:** `xreview.sh
  --brief-only …` prints the filled brief; spawn the project's reviewer agent
  (`.codex/agents/reviewer.toml`, read-only) with that brief as its only
  input. This is a same-model review when the session is Codex too.

## 4. Two reviews of one change

- Phase 6 by one model and a second opinion by another (or the Codex native
  reviewer, below): a finding both surface **independently** is a priority,
  never a duplicate to collapse.
- They disagree on the verdict → **not averaged and not decided by the
  author.** The blocking verdict stands until a person — the risk owner —
  decides with both reports in hand, or a third run receives the disputed
  finding as an explicit question ("is `port.py:12` reachable with `None`?
  cite the line") and answers it with evidence.
- **Codex native review** — `codex exec review --base <branch>` — applies
  the `## Code Review Rules` section of the project's `AGENTS.md`. It does
  not grade the DoD and takes no brief with `--base`, so it is an additional
  opinion, never the phase-6 review itself.

## 5. In the evidence block

```
review @ 3f2a1c9 (codex gpt-6.1-sol, isolated · docs/reviews/DEV-475-3f2a1c9-codex.md)
security @ 3f2a1c9 (claude opus, isolated · docs/reviews/DEV-475-3f2a1c9-claude-security.md)
```

Codex Security in CI (`ci-gate`, optional second security pass) is another
model looking at the same trust boundaries — an LLM layer, not part of the
deterministic gate, and not a substitute for 6b.
