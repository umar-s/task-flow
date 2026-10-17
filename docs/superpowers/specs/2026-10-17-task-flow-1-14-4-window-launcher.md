# task-flow 1.14.4 — a launcher of the project's own in a wave window

## Goal

A wave window runs `claude` / `codex` by the absolute path found on the
launching shell's `PATH`. On a workstation where the CLI is started through a
launcher — a proxy only that CLI may use, a memory limit for an agent's
process — the launcher is often a shell function, which a tmux window cannot
see. The window then starts the bare CLI: no proxy (unless the tmux server
happened to be born with one) and no memory limit. 1.14.4 lets the project name
the command a window runs in place of each CLI.

## Measured (2026-10-17, tmux 3.4)

- A function named in the launching shell is not visible to `sh -c` nor to a
  non-interactive `bash -c` (`command -v` finds nothing).
- A tmux server started without the proxy variables gives its windows none,
  even when the shell that opens the window has them (0 of 2 in the window).
- A live wave of 9 Claude Code windows: each in its own `tmux-spawn-*.scope`
  with `MemoryHigh=infinity`, `MemoryMax=infinity` — the launcher's limit was
  not applied.

## Change

- `TASK_WAVE_CLAUDE_BIN` / `TASK_WAVE_CODEX_BIN`: a name on `PATH` or a path,
  one command. Default when unset: `claude` / `codex` (unchanged behaviour).
- Resolved with `type -P` (an executable file only — never a function, alias or
  builtin), made absolute against the launch directory like the CLI was, and
  put into the window command in the CLI's place; `TASK_WAVE_*_ARGS`, `--` and
  the prompt follow unchanged.
- Not found → the dry-run plan says `not on PATH: <value> (<variable>)`; the
  real run refuses (rc 2) before a fetch, worktree or window.
- Set but empty → rc 2. A value starting with `-` → rc 2, pointing to
  `TASK_WAVE_*_ARGS`.

## DoD

1. Unset, both windows run the CLI itself by its checked absolute path (plan
   text unchanged from 1.14.3).
2. A launcher named by a bare name on `PATH` and one given as a relative path
   both appear in the plan by absolute path.
3. A real run through both launchers: each launcher receives exactly `--` and
   the prompt (plus `TASK_WAVE_*_ARGS` before them), and the CLI it execs
   receives the same.
4. A missing launcher, an exported shell function and a non-executable file are
   all reported as not on PATH with the variable's name; a real run refuses
   before any fetch or tmux session.
5. Empty value and flag value → rc 2, nothing planned.
6. `scripts/lint.sh` pins the default expansion, the `type -P` resolution, the
   absolute path and the per-variable missing check; README.md and README.ru.md
   describe the variables in lockstep; tests pass under bash 3.2.

## Premortem edges

- E1. `command -v` would accept an exported function (`export -f`) and the
  window would fail with "command not found" after the worktree exists →
  `type -P`, test with `export -f`.
- E2. A relative launcher path resolved after `cd` into the worktree points
  elsewhere → made absolute against the launch directory, tested via `rel/cx`.
- E3. An empty variable (an unset shell variable expanded into the export)
  silently falls back to the bare CLI — the very thing the launcher exists to
  avoid → refused.
- E4. A launcher that drops or reorders its arguments loses the prompt → not
  this template's to guard; the README requires `exec <cli> "$@"`.
- E5. The launcher runs with the scrubbed window environment (1.14.3) — it gets
  no agent session variables either; what it adds (a proxy) is its own.
- E6. bash 3.2: `${!v-unset}` indirect expansion with an operator — checked in
  the pinned `bash:3.2` image.
