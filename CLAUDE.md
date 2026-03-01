# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable Claude Code plugins for development workflows, distributed via the Claude Code plugin marketplace. Each plugin is independently installable and contains skills, hooks, MCP servers, or scripts.

Project-level roadmap and investigation items live in `.claude/todo.md`.

## Structure

```
claude-toolkit/                              # marketplace repo
├── .claude-plugin/
│   └── marketplace.json                     # Claude Code marketplace catalog
├── .github/plugin/
│   └── marketplace.json                     # Copilot CLI marketplace catalog
├── plugins/                                 # canonical plugin sources
│   ├── bash-safety/                         # hook: Bash command safety classifier
│   ├── format-on-save/                      # hook: auto-format after Edit/Write
│   ├── notify-on-stop/                      # hook: desktop notification on completion
│   ├── feature/                             # command + skills: feature tracking (1 command, 2 skills, 2 scripts)
│   ├── image/                               # skills: clipboard paste + screenshot (2 skills, 2 scripts)
│   ├── markdown/                            # command: lint, format, setup (1 command, 1 script)
│   ├── convert-doc/                         # skill: pandoc document conversion
│   ├── frontmatter-query/                   # skill: YAML frontmatter queries (1 skill, 2 scripts)
│   ├── jar-explore/                         # skill: JAR content inspection (1 skill, 1 script)
│   ├── maven-indexer/                       # MCP + command: class search/decompile (docker compose)
│   ├── maven-tools/                         # MCP: Maven Central intelligence (docker run)
│   └── permission-manager/                  # hook + command: Bash safety classifier, permission management
├── plugins-copilot/                         # Copilot CLI variants (hook plugins only)
│   └── permission-manager/                  # symlinks + Copilot-format hooks.json
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
├── mcp.json                 # MCP server definitions (declared in plugin.json)
└── scripts/                 # helper scripts (referenced via ${CLAUDE_PLUGIN_ROOT})
```

## Plugin Components

| Type | Location | Format | Discovery |
|------|----------|--------|-----------|
| Skills | `skills/<name>/SKILL.md` | Markdown with YAML frontmatter | Auto-discovered |
| Hooks | `hooks/hooks.json` | JSON with `{hooks: {Event: [...]}}` wrapper | Auto-registered |
| MCP servers | `mcp.json` | JSON with `{mcpServers: {...}}` | Declared in `plugin.json` via `mcpServers` field |
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

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Use kebab-case for all directory and file names
- Skills that are user-initiated (not auto-triggered) set `disable-model-invocation: true`
- Scripts reference siblings via `$(dirname "$0")` for co-located files

## Copilot CLI Compatibility

Both Claude Code and Copilot CLI recognize the same plugin format (`.claude-plugin/`, `skills/`, `hooks/`). However, Claude Code strictly validates hook event keys, rejecting the camelCase format Copilot CLI uses. The two CLIs also use different marketplace discovery paths:

| | Claude Code | Copilot CLI |
|---|---|---|
| Marketplace | `.claude-plugin/marketplace.json` | `.github/plugin/marketplace.json` |
| Hook events | PascalCase (`PreToolUse`) | camelCase (`preToolUse`) |
| Hook format | Nested `hooks` array, `command` key | Flat array, `bash` key, `version: 1` |
| Plugin root var | `${CLAUDE_PLUGIN_ROOT}` | `${COPILOT_PLUGIN_ROOT}` |

**Dual-marketplace approach** — Plugins without hooks (session, image, markdown, etc.) work identically on both CLIs and are listed only in `.claude-plugin/marketplace.json`. Plugins with hooks need a Copilot CLI variant under `plugins-copilot/` that provides a Copilot-format `hooks.json` and symlinks shared directories (scripts, skills, groups) back to the canonical `plugins/` source:

```
plugins-copilot/<name>/
├── .claude-plugin/
│   └── plugin.json          # copy of canonical plugin.json
├── hooks/
│   └── hooks.json           # Copilot CLI format (camelCase, flat, version:1)
├── scripts -> ../../plugins/<name>/scripts
├── skills -> ../../plugins/<name>/skills
└── <other-dirs> -> ../../plugins/<name>/<other-dirs>
```

The Copilot CLI marketplace (`.github/plugin/marketplace.json`) points to the `-copilot` variants for hook plugins only.

**Hook script input** — Claude Code sends `tool_name`/`tool_input` (snake_case); Copilot CLI sends `toolName`/`toolArgs` (camelCase, args as JSON string). Source `hook-compat.sh` to normalize:

```bash
HOOK_INPUT=$(cat)
source "$(dirname "$0")/hook-compat.sh"
# Exports: HOOK_FORMAT, HOOK_TOOL_NAME, HOOK_COMMAND, HOOK_FILE_PATH, HOOK_EVENT_NAME
# hook_ask "reason" / hook_allow "reason" — output correct JSON per CLI
```

**Shared utilities** — `utils/` holds scripts shared across plugins. Symlink into each plugin's `scripts/` with a relative path (`../../../utils/foo.sh`). Both CLIs dereference symlinks on install — each installed plugin gets a standalone copy with no cross-plugin runtime dependency.
