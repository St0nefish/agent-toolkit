# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable Claude Code plugins for development workflows, distributed via the Claude Code plugin marketplace. Each plugin is independently installable and contains skills, hooks, MCP servers, or scripts.

Project-level roadmap and investigation items live in `.claude/todo.md`.

## Structure

```
claude-toolkit/                              # marketplace repo
├── .claude-plugin/
│   └── marketplace.json                     # marketplace catalog (lists all plugins)
├── plugins/
│   ├── bash-safety/                         # hook: Bash command safety classifier
│   ├── format-on-save/                      # hook: auto-format after Edit/Write
│   ├── notify-on-stop/                      # hook: desktop notification on completion
│   ├── session/                             # skills: tracked dev sessions (7 skills, 2 scripts)
│   ├── image/                               # skills: clipboard paste + screenshot (2 skills, 2 scripts)
│   ├── markdown/                            # skills: lint, format, link-check (5 skills)
│   ├── convert-doc/                         # skill: pandoc document conversion
│   ├── frontmatter-query/                   # skill: YAML frontmatter queries (1 skill, 2 scripts)
│   ├── jar-explore/                         # skill: JAR content inspection (1 skill, 1 script)
│   ├── maven-indexer/                       # MCP: class search/decompile (docker compose)
│   ├── maven-tools/                         # MCP: Maven Central intelligence (docker run)
│   └── permission-manager/                  # scaffold: permission group management
```

Each plugin follows this internal layout:

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json          # required: name, version, description
├── skills/                  # auto-discovered skill directories
│   └── <skill-name>/
│       └── SKILL.md         # skill definition with frontmatter
├── hooks/
│   └── hooks.json           # hook event configuration
├── .mcp.json                # MCP server definitions
└── scripts/                 # helper scripts (referenced via ${CLAUDE_PLUGIN_ROOT})
```

## Plugin Components

| Type | Location | Format | Discovery |
|------|----------|--------|-----------|
| Skills | `skills/<name>/SKILL.md` | Markdown with YAML frontmatter | Auto-discovered |
| Hooks | `hooks/hooks.json` | JSON with `{hooks: {Event: [...]}}` wrapper | Auto-registered |
| MCP servers | `.mcp.json` | JSON with `{mcpServers: {...}}` | Auto-started |
| Scripts | `scripts/<name>` | Bash/Python executables | Referenced from skills/hooks |

## Path References

Use `${CLAUDE_PLUGIN_ROOT}` for all intra-plugin path references:
- In skill content: `${CLAUDE_PLUGIN_ROOT}/scripts/my-tool` (resolved at load time)
- In hook commands: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh` (resolved at execution)
- In MCP configs: `${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` (resolved at registration)

Never use hardcoded paths like `~/.claude/tools/...`.

## Installation

Install individual plugins from the marketplace:

```bash
claude plugin install claude-toolkit/session
claude plugin install claude-toolkit/bash-safety
```

Or test locally during development:

```bash
claude --plugin-dir ./plugins/bash-safety
```

## Legacy Structure (deprecated)

The original deployment system (`skills/`, `hooks/`, `mcp/`, `permissions/`, `deploy-rs/`, `deploy`) remains in the repo for reference but is superseded by the plugin structure in `plugins/`. The custom Rust deployer (`deploy-rs/`) is no longer needed — Claude Code's native plugin system handles installation, enable/disable, and updates.

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Use kebab-case for all directory and file names
- Skills that are user-initiated (not auto-triggered) set `disable-model-invocation: true`
- Scripts reference siblings via `$(dirname "$0")` for co-located files
