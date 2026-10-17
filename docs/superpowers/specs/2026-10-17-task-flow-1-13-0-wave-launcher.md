# task-flow 1.13.0 — wave launcher

## Goal
Start every ready task of one `decompose` wave side by side: one git worktree and
one interactive tmux window per task, Claude Code or Codex by the issue's
`builder:*` label, `task` already invoked. Tracker: GitHub Issues via `gh`.

## DoD
1. `templates/wave/task-wave.sh` is portable bash (no bash-4-only builtins such as
   `mapfile`), self-contained (no plugin paths), executable.
2. Ready set = open issues labelled exactly `builder:claude` or `builder:codex`
   whose blocked-by issues (GitHub dependencies API) are all closed. Explicit issue
   numbers override it; a non-number argument is refused.
3. A failure to read the issue list, an issue, or a blocker list stops the run
   with a non-zero exit — it never reads as "no ready task" or "ready".
4. Each started task: worktree `../<repo>-<N>` on branch `task-<N>` from
   `origin/<base>` (`--base` overrides the default branch); an existing worktree is
   resumed; an existing `task-<N>` branch without a worktree is reused.
5. Each started task: a tmux window `#<N>` in session `wave-<repo>`, cwd = its
   worktree, running `claude '/task-flow:task #N'` or `codex '$task-flow:task #N'`
   — the prompt reaches the CLI byte-exact (the `$` survives the shell).
6. `--dry-run` creates nothing (no worktree, no session, no fetch).
7. The script never merges, pushes or deletes; sessions stay interactive.
8. No tmux on PATH (outside a dry run) → refused before anything is created.
9. `tests/task-wave.sh` covers 2–8 offline (stub gh with jq over fixtures, stub
   CLIs, private tmux server) and is run by `tests/run.sh` in CI (tmux installed
   there if missing).
10. lint pins: syntax/executable, no unmarked fail-open idiom, the refuse-to-guess
    rule, no `gh pr merge`/`git push`, `decompose` Handoff and both READMEs name it;
    README.md and README.ru.md stay in structural parity.
11. CHANGELOG 1.13.0 states what changed, the supply-chain self-check (network:
    `git fetch`, `gh` reads), and the version in plugin.json is 1.13.0.
12. Round 1 fixes hold: the ready set reads every page (`gh api --paginate`, label
    filter server-side, pull requests dropped) with no count limit; an existing
    path is resumed only as this repository's worktree on `task-<N>` (canonical
    path in `git worktree list --porcelain`), otherwise the run stops before any
    worktree or window exists; controls cover an `issue view` failure, no fetch
    in a dry run, and a real `--base` start point on a commit only that branch has.
13. Round 2 fix holds: each issue's blocked-by list is read on every page
    (`--paginate`); ready = no open blocker on any page; a failure on any page
    stops the run; controls put an open blocker on page 2 and fail page 2 after
    page 1 was printed.
14. Round 3 fix holds: the harness CLIs a wave needs are checked before fetch,
    worktree or window (a real run refuses, a dry run warns); an issue with both
    builder labels is skipped, not guessed.
15. Round 4 fixes hold: a task whose window `#<N>` is alive in the wave's session
    is not started again (no second agent in one checkout); a `task-<N>` branch
    checked out in a worktree other than `../<repo>-<N>` is refused in the plan,
    before fetch, worktree or window.
16. Round 5 fix holds: an issue number given twice (`2 2`, `2 #2`) is planned
    once — one window, one launch — for a new and for a resumed worktree.
17. Round 6 fix holds: one launcher per repository at a time — an atomic
    `mkdir` lock in the git common dir, taken before the window check and released
    on exit; a second concurrent run is refused (rc 2), never a second agent.
18. Round 7 fix holds: the window runs the CLI by the absolute path the plan
    checked, with the launcher's PATH (`env PATH=… /abs/cli …`), so a window
    whose environment differs from the launcher's still runs it — including a CLI
    whose `#!/usr/bin/env <interp>` lives outside `/usr/bin:/bin`.
19. Round 8 fixes hold: the CLI path and every relative PATH entry (an empty one
    included) are made absolute against the launcher's directory before the window
    starts in the worktree; `tests/task-wave.sh` runs under a real bash 3.2 in CI
    (pinned `bash:3.2` image), not only under the lint's construct ban.
20. Round 9 fixes hold: an issue number is read as canonical decimal (`02`, `#2`
    and `2` are one issue — one plan entry, one window, the live-window check
    included); the controls that count launches wait for the stub CLI (bounded),
    then watch 0.5 s more for an extra one.
21. Round 10 fix holds: the session `wave-<repo>` carries its owner
    (`@task_wave_repo` = the canonical git common dir, set in the same tmux call that
    creates it); a session of that name owned by another repository, or by nobody,
    is refused before fetch, worktree or window — never read as "already running".

## Premortem edges

Imagined failures of the launcher, each mapped to the control in
`tests/task-wave.sh` that catches it, or to an explicit exclusion.

| # | Failure mode | Control / exclusion |
|---|---|---|
| E1 | A ready task is hidden by a count limit on the issue list | case 1: ready #350 past item 100 of its label and 200 of all issues; stub serves 100-item pages without `--paginate` |
| E2 | An open blocker past the blockers' first page reads as ready | case 1: #360's open blocker on page 2 (30/page default) |
| E3 | A failed tracker read reads as "none" or "ready" | case 3: each label page, an issue view, a blocker list, and page 2 failing after page 1 printed → rc 2 |
| E4 | A pull request carrying a builder label is started as a task | case 1: #7 (`pull_request` set) not in the ready set |
| E5 | A task with both builder labels starts in an arbitrary harness | case 2: #380 skipped, explicit and in the ready set |
| E6 | A wave needs a harness not installed — the window dies, success is reported | case 4b: rc 2 before fetch/worktree/window; dry run warns; a claude-only wave still starts |
| E7 | tmux missing — worktrees created, nothing runs | case 4: rc 2, no worktree, no fetch |
| E8 | A foreign directory or a worktree on another branch sits at the task's path; the agent runs in the wrong checkout | case 5: plain dir and `other` branch → rc 2 |
| E9 | One refused task leaves the others half-started | case 5: #2 not started when #5 is refused (plan before start) |
| E10 | The prompt is mangled by the shell (`$task-flow` expanded) | case 6: codex argv is exactly `$task-flow:task #5` |
| E11 | A session runs outside its worktree | case 6: recorded cwd of each stub |
| E12 | Re-running a wave duplicates or recreates work — a second agent in the same checkout | case 7: a live window `#2` → not started again (window and launch counts unchanged); once the window is gone the worktree is resumed; case 8: leftover `task-N` branch reused |
| E13 | The wrong start point (default branch instead of the integration one) | case 9: `--base develop` → HEAD = a commit only develop has |
| E14 | A dry run has side effects | case 1: no worktree, no session, no fetch (git wrapper counts) |
| E15 | The script lands work by itself | lint: no `gh pr merge` / `git push`; nothing in the script deletes |
| E16 | bash-4-only syntax or semantics break on macOS bash 3.2 (e.g. `"${a[@]}"` of an empty array under `set -u`) | lint bans the bash-4-only constructs; CI runs the whole suite under bash 3.2.57 (pinned `bash:3.2` image) — 39/39 |
| E17 | Launched from inside an existing tmux session | Exclusion: `new-session -d` and `-t =wave-<repo>` work the same from inside tmux; the controls run with `TMUX` unset on a private server |
| E18 | GitHub without the blocked-by API (older GHES) | covered by E3: the blocker read fails → rc 2, never "ready"; README names GitHub Issues as the tracker |
| E19 | `task-N` is checked out in another worktree; `git worktree add` fails mid-run and the wave starts half-way | case 5b: refused in the plan, #2 not started, no fetch |
| E20 | The same issue named twice — also as `#2` or `02` — starts two agents in one checkout | case 5c: `2 2 02` (new) and `2 #2 002` (resumed) → one window, one launch, no `lab-02`; case 7: `02` beside a live `#2` → not started |
| E21 | Two launchers run at once; both see no window #N and both start an agent in one checkout | case 7b: concurrent runs on a resumable task → one starts, the other is refused by the lock; one window, one launch; the lock is released after |
| E22 | The window's environment differs from the launcher's (tmux version, update-environment, default-command); the checked CLI or its `env` interpreter is not found there | case 10: a tmux shim runs the client with `PATH=/usr/bin:/bin`, the stubs' interpreter lives only in the test bin (as node in nvm's) → the CLI still runs. Measured: tmux 3.4 gives a new window the creating client's PATH, so the shim models the other setups |
| E23 | The CLI or its interpreter is found through a relative PATH entry, valid in the launcher's directory but not in the worktree the window starts in | case 11: `PATH=relbin:…` with the CLI and its `env` interpreter only there → still starts |
| E24 | Two checkouts with the same basename share `wave-<name>`; one takes the other's live `#N` for its own and silently skips its task | case 7a: `…/other/lab` beside a running `lab` wave → rc 2, nothing created; an unmarked `wave-solo` → rc 2 |
