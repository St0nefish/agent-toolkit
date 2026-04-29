---
user-invocable: false
name: serena-setup
description: >-
  Install the Serena MCP server and register it with Claude Code. Use when the
  user asks to "install Serena", "set up Serena", "configure Serena MCP", or
  when `mcp__serena__*` tools are unavailable / the Serena MCP server is
  disconnected and needs to be installed. Installs via `uv tool install`
  (Python — no Node.js / npm involved) and writes the MCP server entry to
  `~/.claude.json`.
---

# Serena setup

Serena is a Python project distributed via the `oraios/serena` GitHub repo.
It exposes a stdio MCP server (`serena start-mcp-server`) that brings
language-server-driven code intelligence into Claude Code.

## Prerequisites

- `uv` (Astral's Python package manager) — install via:

  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

  Or via system package manager (Arch: `pacman -S uv`).

Serena's source tree includes Node.js artifacts only as a transitive concern;
**this skill never touches npm/node/npx.** Installation is pure Python via uv.

## Install

```bash
uv tool install --from git+https://github.com/oraios/serena serena
```

This puts the `serena` binary at `~/.local/bin/serena` (ensure that's on
`PATH`). Verify:

```bash
which serena && serena --version
```

To upgrade later: `uv tool upgrade serena`.

## Register with Claude Code

Add an MCP server entry to `~/.claude.json`. The recommended invocation:

```json
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "serena",
      "args": [
        "start-mcp-server",
        "--context",
        "claude-code",
        "--project-from-cwd"
      ],
      "env": {}
    }
  }
}
```

Key flags:

- `--context claude-code` — Serena tunes its behavior (prompts, tool descriptions) for Claude Code.
- `--project-from-cwd` — Serena auto-detects the active project from the current
  working directory. No per-project config needed.

The entry can live at user level (`~/.claude.json` top-level `mcpServers`) for
all projects, or per-project under `.projects[<path>].mcpServers`.

## Disable memories (recommended)

Serena's "memories" feature stores opaque sidecar notes that aren't
source-controlled. Disable it for source-of-truth-in-the-repo workflows.

Add to your Serena project config (`.serena/project.yml` or via CLI flag):

```yaml
# .serena/project.yml
disable_memories: true
disable_onboarding: true
```

Or pass `--disable-memories --disable-onboarding` to the `start-mcp-server`
args. With memories disabled, the memory MCP tools (`write_memory`,
`read_memory`, etc.) won't appear in the tool list, and the onboarding flow
won't trigger.

## Verify

After registering and reconnecting Claude Code:

1. `mcp__serena__*` tools should appear in the available tool list (some
   surfaces show them as "deferred" until first use).
2. Calling `mcp__serena__initial_instructions` should return Serena's
   manual without errors.
3. Calling `mcp__serena__get_symbols_overview` on a source file in your
   project should return structured symbol data.

If tools don't appear, check:

- `serena` is on `PATH` (`which serena`)
- The MCP entry uses `"type": "stdio"` and the correct args
- Claude Code has reconnected (toggle the MCP server, or restart the session)
- Logs: Serena writes to `~/.serena/logs/` by default

## See also

- The `serena-cheatsheet` skill (this plugin) covers usage quirks once Serena
  is running.
- The `serena-explorer` agent (this plugin) handles verbose meta-analysis
  queries.
