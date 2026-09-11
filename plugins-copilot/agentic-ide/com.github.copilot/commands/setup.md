---
description: "Install the agentic-ide tools: Serena MCP, Semgrep MCP, ast-grep CLI"
disable-model-invocation: true
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
echo "Serena is registered automatically by this plugin and starts on first use."
```

## Prerequisite for Serena and Semgrep

Both MCP servers install via `uv` (Astral's Python package manager):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # universal
# or: brew install uv / pacman -S uv
```

---

## Serena (LSP symbol intelligence)

The Copilot plugin registers a shared Serena bridge automatically. The first Serena-enabled session
in each Git worktree installs Serena with `uv` if needed and starts one localhost-only backend for
that worktree. Other Copilot sessions in the same worktree connect through lightweight bridges,
instead of each launching a separate Serena and language server.

Create the Serena mode config if you do not already have one:

```bash
mkdir -p ~/.serena

cat > ~/.serena/serena_config.yml <<'YAML'
base_modes:
  - no-memories
YAML
```

- `--context=copilot-cli` tunes prompts and tool descriptions for Copilot CLI.
- `~/.serena/serena_config.yml` with `base_modes: [no-memories]` disables memories and onboarding tools globally. If you need a one-off invocation instead, pass `--mode interactive --mode editing --mode no-memories` to `serena start-mcp-server` and re-list any other modes you want.

The shared bridge requires `systemd --user`, `git`, `flock`, Python 3, and `uv`. It keeps its
per-worktree state under `${XDG_RUNTIME_DIR:-/tmp}/agentic-ide-serena-<uid>/`; transient backend
services are named `agentic-ide-serena-<worktree-sha256>.service`. Use
`systemctl --user status <service>` and `~/.serena/logs/` to investigate startup failures.

Remove any manually configured direct `serena` stdio entry from `~/.copilot/mcp-config.json`
after confirming the plugin-provided server appears in `copilot mcp list`. A direct entry defeats
sharing by starting a separate backend per Copilot session.

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

Register the server with Copilot CLI — via `copilot mcp add`:

```bash
copilot mcp add semgrep -- semgrep-mcp
```

Optional: add `SEMGREP_APP_TOKEN` to `env` to enable `semgrep_findings` (pulls from Semgrep AppSec Platform). Generate at <https://semgrep.dev/orgs/-/settings/tokens>. All local-scan tools work without it.

Restart the Copilot CLI session. `semgrep-*` tools should appear; `semgrep-supported_languages` should return a language list.

---

## Troubleshooting

If MCP tools do not appear:

- `which <command>` — binary must be on `PATH`
- Verify the plugin server with `copilot mcp list`; restart the Copilot CLI session, or toggle it with `/mcp`
- Run `systemctl --user status agentic-ide-serena-<worktree-sha256>.service` after the bridge has started
- Tools load but never surface to the assistant → see Copilot CLI issue [#191](https://github.com/github/copilot-cli/issues/191) (third-party MCP servers may register without exposing their tools)
- Scans failing with `Semgrep is not installed or not in your PATH` → the `semgrep` engine binary isn't on `PATH`; reinstall with `uv tool install semgrep-mcp --with-executables-from semgrep`
