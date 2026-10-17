# task-flow 1.14.3 — the window's command line as a real CLI reads it

## Goal

Two defects of `templates/wave/task-wave.sh` reported from the first live wave on a
GitLab + YouTrack workspace (a project's wrapper had worked around both). The
130 controls of 1.14.2 did not see them: the stub CLIs record argv and never parse
it the way commander (claude) or clap (codex) do, and the window environment was
never looked at.

## Measured (2026-10-17, claude 2.1.302, codex-cli 0.163.0, private tmux socket)

- `claude --mcp-config <file> '/task-flow:task X-1'` → `Invalid MCP configuration:
  MCP config file not found: /task-flow:task X-1`, rc 1: `--mcp-config` takes
  several values and takes the prompt as one more.
- `codex -i <file> '$task-flow:task X-1'` → the TUI starts with `[Image #1]
  [Image #2]` and an empty prompt: `--image` takes several values; the window
  stays up, without its task.
- With `--` before the prompt both start with the prompt (`codex -- --version`
  takes `--version` as the prompt: clap honours `--`).
- A tmux server started from an agent's shell carries that agent's variables
  (12 in a Claude Code 2.1.302 session: `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`,
  `CLAUDE_CODE_MESSAGING_SOCKET`/`_TOKEN`, `CLAUDE_CODE_BRIDGE_SESSION_ID`, …);
  every window of that server gets them, whatever shell later asks for the window.
  The report's "a nested claude refuses to start" did **not** reproduce on 2.1.302
  (it starts); the leak of the parent's session ids and messaging channel stands.

## DoD

1. Both window commands put `--` between the CLI's flags and the prompt; with
   `TASK_WAVE_*_ARGS` empty too.
2. A `--` that ends `TASK_WAVE_CLAUDE_ARGS` / `TASK_WAVE_CODEX_ARGS` (the
   workaround a project already ships) is dropped, never doubled. A `--` followed
   by another word in either variable → rc 2 before anything is planned.
3. The window command unsets, through `env -u`, every variable of xreview.sh's
   families (`CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_PLUGIN_*`, `CLAUDE_ENV_FILE`,
   `CLAUDE_PROJECT_DIR`, `CLAUDE_EFFORT`, `CLAUDE_PID`, `CODEX_SESSION_ID`,
   `CODEX_THREAD_ID`, `CODEX_CI`, `CODEX_SANDBOX*`, `PLUGIN_ROOT`, `PLUGIN_DATA`,
   `PP_*`, `PREDICT`) found in this shell, in the running tmux server's global
   environment, or in the wave session's environment. Kept: the auth variables
   xreview.sh keeps (`CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_*`,
   `CLAUDE_CODE_SKIP_*_AUTH`, `CLAUDE_CODE_CLIENT_*`) and every name in
   `TASK_WAVE_KEEP_ENV`.
4. Only names are kept from tmux: `show-environment` prints `NAME=value`, and the
   pipe through `sed` keeps the name, so no value is held in a variable or printed.
   An unreadable tmux environment, global or the session's → rc 2 before anything
   is planned.
5. Controls: the `--` in planned and launched commands on both trackers; trailing
   `--` dropped; a mid `--` refused; the window's environment without the agent's
   variables when task-wave starts the server, when a server already holds them,
   and when the wave session holds one; auth and `TASK_WAVE_KEEP_ENV` kept. Every
   new guard caught by a mutation; the suite green under bash 3.2.
6. Live: the planned commands, run on a private tmux server that holds all 12
   variables, start the real claude and codex with the prompt, and
   `/proc/<pid>/environ` of each CLI holds none of them.

## Premortem edges

| # | How it fails | Control |
|---|---|---|
| E1 | A project's wrapper already ends `TASK_WAVE_CLAUDE_ARGS` with `--` (the documented 1.14.2 workaround): a second `--` makes the first `--` the prompt. | Z3 "a '--' ending TASK_WAVE_*_ARGS is dropped, not doubled — claude and codex"; mutation "trailing -- not dropped". |
| E2 | `--` in the middle of the variable: every flag after it, and the prompt, become positionals. | Z3 two "before another flag … rc 2" controls (claude, codex); mutation "mid -- not refused". |
| E3 | The fix lands in one CLI only: codex keeps losing its prompt to `--image`. | `--` asserted in planned commands (both trackers) and in the launched argv of both stubs; mutations "claude prompt without --", "codex prompt without --"; lint pin counts 2. |
| E4 | The scrub reads only this shell: a tmux server first started from an agent keeps its variables, and every later window gets them. | Z3 "a server already up with an agent's variables" (foreign session up first, checked); mutation "tmux server env not read". |
| E5 | A variable set in the wave session's own environment (`update-environment`, `set-environment -t`) reaches a new window. | Z3 session control with a name no other source holds; mutation "tmux session env not read". |
| E6 | Over-scrubbing removes the CLI's own auth (OAuth token, Bedrock/Vertex selection, client certs): every window asks to log in. | Z3 "auth families and TASK_WAVE_KEEP_ENV stay, in both windows"; mutations "auth not kept", "TASK_WAVE_KEEP_ENV ignored". |
| E7 | `tmux show-environment` fails (server gone between calls): the scrub list silently shrinks and the wave starts leaky. | Z3 two "unreadable → rc 2" controls via a tmux wrapper; mutations "tmux … env failure ignored". |
| E8 | Values reach the plan output or a variable (tokens live in that environment). | Only names leave the `sed`; the plan prints `-u NAME`. Reviewed by reading; no control. |
| E9 | bash 3.2 (macOS): `unset "a[i]"`, `${a[@]+…}` on an emptied array. | Suite under the pinned `bash:3.2` image (CI and local). |
