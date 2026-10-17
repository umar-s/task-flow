# task-flow 1.14.0 — the wave launcher on YouTrack; decompose writes the builder

## Goal
`templates/wave/task-wave.sh` starts a wave from **YouTrack** as well as from
GitHub Issues: one file, one launcher core, two tracker adapters chosen by
`--tracker github|youtrack`. Everything 1.13.0 hardened (lock, worktree and branch
checks, live-window check, session owner, absolute CLI paths) stays shared. The
YouTrack side runs with GitLab as the VCS: no `gh` in that mode. `decompose`
phase 7 writes each task's builder (`builder:claude` / `builder:codex`) as a
YouTrack tag or a GitHub label, so a pushed epic is launchable without a hand step.

## Measured on a live YouTrack (2026-10-17, read-only unless named)
- REST base is the instance root: `<url>/api/...`; a wrong base (`/youtrack` on a
  root install) answers **HTTP 200 with an HTML page**.
- `GET /api/issues?query=…` without `$top` returns **at most 500 items, silently**
  (project with 1505 issues). `$top=100&$skip=N` pages without overlap.
- A query naming a tag that does not exist (`tag: {builder:claude}` before any
  issue carries it) is **HTTP 400 `invalid_query`**, not an empty list.
- Blockers of A = `is required for: A` (link type `Depend`, `INWARD` in A's
  `links`); compared against `links` on two issues per instance. Link-type names
  are per instance: a second instance also has `Blocks` (`blocks: A`).
- `is required for: <id that does not exist>` → HTTP 400; `GET /api/issues/<id>`
  → 404. `dev-1243` and `DEV-01243` both return `idReadable` `DEV-1243`.
- `subtask of: E #Unresolved` lists E's open subtasks; `sort by: created asc`
  inside the query works.
- The command `tag builder:claude` (`/api/commands`) creates the tag on first use
  ("Добавить новый тег"); fixtures DEV-1554…1559 were created with it (writes
  authorised by the owner for this test).

## DoD
1. One file; `--tracker github|youtrack` (else `TASK_WAVE_TRACKER`, else
   `github`): **1.13.0 behaviour is unchanged without the flag** — every existing
   control in `tests/task-wave.sh` passes unmodified.
2. YouTrack configuration from the environment only: `YOUTRACK_URL` (must be
   `https://…`; trailing `/` dropped), `YOUTRACK_TOKEN_VAR` = the **name** of the
   variable holding the token (default `YOUTRACK_TOKEN`). Missing URL, an `http://`
   URL, a bad variable name, an empty token or a token with characters outside
   `[A-Za-z0-9._:+/=-]` → rc 2 before any request.
3. The token never reaches argv: `curl --config -` reads the
   `Authorization: Bearer` header from stdin (bash builtin `printf`).
4. Every response must be HTTP 2xx **and** parse as the JSON shape expected
   (array for a search, object with `idReadable` for an issue); anything else —
   4xx/5xx, HTML, truncated JSON — stops the run with rc 2 ("refusing to guess").
5. Ready set (youtrack): needs `--project KEY` or `--epic ID` (both allowed:
   AND). Query `[project: KEY] [subtask of: ID] #Unresolved sort by: created asc`,
   read in pages of `$top=100` until a short page; tags filtered client-side (no
   tag in the query — DoD measured 400). Exactly one builder tag → candidate; both
   → skipped with a message; none → ignored. Candidate is ready when every
   blocker query `<name>: <ID> #Unresolved` (each name in `YOUTRACK_BLOCKER_LINKS`,
   `;`-separated, default `is required for`) returns no issue on any page.
   (As built: a blocker search asks `$top=1` — one unresolved blocker already
   decides "blocked", and an empty first page of a complete search is "none";
   Codex round 4 accepted the deviation.)
6. Explicit IDs (youtrack): `^[A-Za-z][A-Za-z0-9_]*-[0-9]+$`, read with
   `GET /api/issues/<id>`; the canonical id is the server's `idReadable` —
   duplicates are removed on it (`dev-5`, `DEV-05` → one task). 404 → rc 2.
   Readiness is not checked for explicit IDs (as on GitHub: naming is the choice).
7. Labels per tracker: GitHub `#N` (window `#N`, worktree `../<repo>-N`, branch
   `task-N`, prompt `/task-flow:task #N`); YouTrack `DEV-481` (window `DEV-481`,
   worktree `../<repo>-DEV-481`, branch `task-DEV-481`, prompt
   `/task-flow:task DEV-481` / `$task-flow:task DEV-481`).
8. Base branch: GitHub as before (`gh` default branch); YouTrack — `--base`, else
   ~~`origin/HEAD` (`git symbolic-ref`); unset → rc 2 naming `--base` and
   `git remote set-head origin --auto`~~ — amended in 1.14.1: origin's own
   default branch (`git ls-remote --symref origin HEAD`); a failed read or an
   answer without a symbolic HEAD → rc 2 naming `--base`; a stale local
   `origin/HEAD` is reported, never used.
9. Tool checks per tracker: github needs `gh`; youtrack needs `curl` and `jq` —
   missing → rc 2 before any request; `gh` is not needed for youtrack.
10. `decompose`: the approval may give each task a builder; the draft's task
    table gains a `Builder` column (a dispatch annotation, not a seventh author
    field; empty = none). Phase 7's plan lists it, the write adds it as tag/label
    `builder:<claude|codex>`, the read-back compares it. Adapter contract:
    `create_issue`/`update_issue` take `tags?`, `read_issue` returns `tags`.
    YouTrack: command `tag builder:<x>`; GitHub: label.
11. Tests: a stub `curl` (bash + jq, works in the bash:3.2 image) serving a
    YouTrack fixture db: pagination past item 200, the 500 silent cap without
    `$top`, 400 on unknown tag / unknown id in a query, 404 on GET, HTML body,
    failure on page 2, argv never holds the token; plus every refusal in 2/4/8/9.
    Mutations of each new guard are caught.
12. lint pins the new guards; README.md/README.ru.md describe both trackers in
    parity; decompose Handoff offers the launcher for both.

## Premortem edges
- E1 Silent 500 cap → a ready task past item 500 never launches (or a blocker past
  it is missed → a blocked task launches). Guard: always `$top`, page to a short
  page. Control: fixture > 500 with the ready one past it.
- E2 Tag absent on the instance → 400 read as "no ready task". Guard: no tag in
  the query; but a 400 elsewhere is still a stop.
- E3 Wrong base URL → HTML 200 parsed as empty. Guard: JSON shape check.
- E4 Token in argv (`-H "Authorization: …"`) → visible in `ps`, shell history,
  tmux logs. Guard: `--config -`; control asserts the stub's argv.
- E5 Token in a window's environment: the launcher exports nothing new; a
  window's environment is tmux's (as in 1.13.0). Not a guard — documented.
- E6 `DEV-05` and `DEV-5` → two windows in one worktree? No: canonical
  `idReadable` dedup. Control.
- E7 Link-type name renamed on an instance (`is required for` absent) → 400 →
  stop (rc 2), not "no blockers". Control: unknown-name 400.
- E8 Blocker read fails on page 2 → must not read as ready. Control.
- E9 Resolved state changes between pages (issue resolved mid-listing) → a skip
  shifts by one; the run may miss one task — it never starts a wrong one (every
  candidate's blockers are read individually). Accepted, named in the help text.
- E10 `origin/HEAD` unset on a fresh GitLab clone → refuse, tell how to set it.
  **Superseded in 1.14.1:** the local `origin/HEAD` is a cache that named feature
  branches in four of five real clones; the base is now `git ls-remote --symref
  origin HEAD`, an unset local pointer is fine, and no answer / no symbolic HEAD
  from origin is the refusal (DoD-8 as amended).
- E11 Window name `DEV-481` and `#2` share the live-window check: matching is on
  the full name with spaces around it (no `DEV-48` ⊂ `DEV-481`). Control.
- E12 GitHub mode must not start requiring curl/jq: `gh` carries its own jq.
- E13 decompose writes a tag on the wrong issue on a partial failure → phase 7's
  stop-on-failure and read-back already cover tags once `read_issue` returns them.
- E14 (found in the live acceptance, not foreseen above — E7 assumed a 400) An
  unknown link name is **not** a 400: YouTrack runs `blocks: DEV-1557` as a text
  search (it returned DEV-1557 itself, "blocked" in its title) and
  `precedes: DEV-1557` as one that finds nothing — a renamed or localised link
  type would make every blocked task ready. Guard: every name in
  `YOUTRACK_BLOCKER_LINKS` must be a `sourceToTarget`/`targetToSource` of
  `/api/issueLinkTypes`, else rc 2. The stub now models the text search.
- E16 (automated security review of the commit) A server id is data and becomes
  a tmux window name — tmux 3.4 runs `#(…)` in `-n` (measured). Guard: a server
  `idReadable` must match `KEY-N`; every `#` in a window name is doubled.
- E17 (Codex round 1) `3xx` + JSON passed `curl -f`; `;` as the link list meant
  no blocker check; an exclusive builder written as "add only" left both tags.
- E15 (found in testing) `yt_blocked` runs as an `if` condition, where `set -e`
  is off: a failed read must `exit 2` by hand. A missing `grep` broke the page
  count and stopped paging silently — pages are counted with `jq length`.
