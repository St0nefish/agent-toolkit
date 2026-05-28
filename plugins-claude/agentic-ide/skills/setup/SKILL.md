---
disable-model-invocation: true
name: setup
description: "Install the agentic-ide tools: Serena MCP, Semgrep MCP, ast-grep CLI"
allowed-tools: Bash
---

# agentic-ide setup

Status check first, then install instructions per tool. Run the bash block to see what's missing, then follow the section(s) for any `✗` entries.

## Status check

```bash
echo "=== agentic-ide tool status ==="
echo
if command -v ast-grep &>/dev/null; then
  echo "✓ ast-grep    $(ast-grep --version 2>&1 | head -1)"
else
  echo "✗ ast-grep    not installed"
fi
if command -v serena &>/dev/null; then
  echo "✓ serena      $(serena --version 2>&1 | head -1)"
else
  echo "✗ serena      not installed"
fi
if command -v semgrep-mcp &>/dev/null; then
  echo "✓ semgrep-mcp installed"
else
  echo "✗ semgrep-mcp not installed"
fi
if command -v semgrep &>/dev/null; then
  echo "✓ semgrep     $(semgrep --version 2>&1 | head -1)"
else
  echo "✗ semgrep     not on PATH (semgrep-mcp scans will fail)"
fi
echo
echo "MCP servers must also be registered in ~/.claude.json — see sections below."
```

## Prerequisite for Serena and Semgrep

Both MCP servers install via `uv` (Astral's Python package manager):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # universal
# or: brew install uv / pacman -S uv
```

---

## Serena (LSP symbol intelligence)

Install:

```bash
uv tool install --from git+https://github.com/oraios/serena serena
```

Verify: `which serena && serena --version`. Upgrade later with `uv tool upgrade serena`.

Register in `~/.claude.json` (user-level `mcpServers`, or per-project under `.projects[<path>].mcpServers`):

```json
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "serena",
      "args": [
        "start-mcp-server",
        "--context", "claude-code",
        "--project-from-cwd",
        "--disable-memories",
        "--disable-onboarding"
      ],
      "env": {}
    }
  }
}
```

- `--context claude-code` tunes prompts and tool descriptions.
- `--project-from-cwd` auto-detects the project — no per-project config needed.
- `--disable-memories --disable-onboarding` skips Serena's opaque sidecar notes; project context belongs in source-controlled files.

Reconnect Claude Code. `mcp__serena__*` tools should appear; `mcp__serena__get_symbols_overview` on a source file should return structured data. Logs at `~/.serena/logs/`.

---

## ast-grep (structural search and rewrite)

```bash
cargo install ast-grep --locked
# or: brew install ast-grep
```

Verify: `ast-grep --version`. No MCP registration — it's a plain CLI.

---

## Semgrep (security and dataflow)

`semgrep-mcp` shells out to the `semgrep` scan engine at runtime, so the `semgrep` binary must be on `PATH`. `uv tool install` only links the primary tool's entry point, so install the engine's executable alongside it:

```bash
uv tool install semgrep-mcp --with-executables-from semgrep
# --with-executables-from also links the `semgrep` engine binary onto PATH
# equivalent: pipx install semgrep-mcp && pipx install semgrep
```

Verify: `which semgrep semgrep-mcp && semgrep --version`. Both binaries must resolve; if `semgrep` is missing, MCP scans will fail. Upgrade later with `uv tool upgrade semgrep-mcp`.

Register in `~/.claude.json`:

```json
{
  "mcpServers": {
    "semgrep": {
      "type": "stdio",
      "command": "semgrep-mcp",
      "args": [],
      "env": {}
    }
  }
}
```

Optional: add `SEMGREP_APP_TOKEN` to `env` to enable `semgrep_findings` (pulls from Semgrep AppSec Platform). Generate at <https://semgrep.dev/orgs/-/settings/tokens>. All local-scan tools work without it.

Reconnect Claude Code. `mcp__semgrep__*` tools should appear; `mcp__semgrep__supported_languages` should return a language list.

---

## Troubleshooting

If MCP tools don't appear after registration:

- `which <command>` — binary must be on `PATH`
- MCP entry uses `"type": "stdio"` and the binary name as `command`
- Restart the Claude Code session, or toggle the MCP server entry
- Scans failing with `Semgrep is not installed or not in your PATH` → the `semgrep` engine binary isn't on `PATH`; reinstall with `uv tool install semgrep-mcp --with-executables-from semgrep`
