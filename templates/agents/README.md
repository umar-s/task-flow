# templates/agents — one instruction source for two harnesses

Copied into a consuming repository once (`task` and `decompose` point here from
their *Harness* section). Rename on copy:

| Template | Goes to | Read by |
|---|---|---|
| `AGENTS.md.skeleton` | `AGENTS.md` | Codex (only this file), and Claude Code through the import below |
| `CLAUDE.md.skeleton` | `CLAUDE.md` | Claude Code — first line `@AGENTS.md`, then Claude-only notes |
| `.codex/config.toml.skeleton` | `.codex/config.toml` | Codex, project layer — loaded only for a trusted project |
| `.codex/agents/reviewer.toml` | `.codex/agents/reviewer.toml` | Codex's own subagents: the read-only phase 6/6b reviewer role |
| `.codex/rules/git.rules` | `.codex/rules/git.rules` | Codex execpolicy: which git commands may leave the sandbox |

Why two instruction files and not one: sessions of both harnesses work in one
directory, and each writes to *its* file (`#` notes in Claude Code append to
`CLAUDE.md`, `/init` in Codex creates `AGENTS.md`). A `CLAUDE.md` that appears
later without the import silently hides `AGENTS.md` from Claude Code, so it
exists from the start and imports it. Codex has no include mechanism —
`AGENTS.md` must stand alone, under Codex's 32 KiB `project_doc_max_bytes`
(longer text is cut silently: keep the rules, move the detail to `docs/`).

Check the rules file before relying on it:

```bash
codex execpolicy check --pretty --rules .codex/rules/git.rules -- git push origin feature/x        # allow
codex execpolicy check --pretty --rules .codex/rules/git.rules -- git push --force origin main     # forbidden
```
