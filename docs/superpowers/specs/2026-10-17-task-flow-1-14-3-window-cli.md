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
4. Only names are read from tmux; an unreadable tmux environment → rc 2.
5. Controls: the `--` in planned and launched commands on both trackers; trailing
   `--` dropped; a mid `--` refused; the window's environment without the agent's
   variables when task-wave starts the server, when a server already holds them,
   and when the wave session holds one; auth and `TASK_WAVE_KEEP_ENV` kept. Every
   new guard caught by a mutation; the suite green under bash 3.2.
6. Live: the planned commands, run on a private tmux server that holds all 12
   variables, start the real claude and codex with the prompt, and
   `/proc/<pid>/environ` of each CLI holds none of them.
