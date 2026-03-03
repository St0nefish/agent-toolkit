# Agent Toolkit

A collection of Claude Code and GitHub Copilot CLI plugins for development workflows. Each plugin is independently installable from the marketplace.

## Plugin Catalogue

### Productivity

| Plugin | Type | Description |
|--------|------|-------------|
| `format-on-save` | Hook | Auto-formats files after Edit/Write using language-appropriate formatters (`shfmt`, `prettier`, `markdownlint`, `google-java-format`, `ktlint`, `rustfmt`, `ruff`) |
| `notify-on-stop` | Hook | Desktop notification when Claude finishes a long-running task (configurable threshold) |
| `feature` | Command + Skills | Feature tracking — start, end, checkpoint, status, catchup, handoff, resume |
| `image` | Skills | Clipboard paste and screenshot capture for macOS, WSL, and Linux |
| `markdown` | Command | Markdown linting and formatting — check, format, setup |
| `convert-doc` | Skill | Convert documents to/from markdown using pandoc (DOCX, HTML, RST, EPUB, ODT, RTF, LaTeX) |

### Development

| Plugin | Type | Description |
|--------|------|-------------|
| `frontmatter-query` | Skill | Query YAML frontmatter across markdown files — list, search, and count metadata |
| `jar-explore` | Skill | List, search, and read files inside JARs without extraction |
| `maven-indexer` | MCP + Command | Class search and decompilation in Gradle/Maven caches (Docker Compose) |
| `maven-tools` | MCP | Maven Central intelligence — version lookup, dependency analysis (Docker) |

### Security

| Plugin | Type | Description |
|--------|------|-------------|
| `permission-manager` | Hook + Command | Bash command gating with shfmt-based compound parsing, extensible custom patterns, and WebFetch domain management |

## Installation

### Claude Code

```bash
claude plugin install <owner/repo>/plugin-name
```

Example:

```bash
claude plugin install lgagne/agent-toolkit/format-on-save
claude plugin install lgagne/agent-toolkit/permission-manager
```

### GitHub Copilot CLI

```bash
copilot plugin install <owner/repo>/plugin-name
```

Hook plugins have a Copilot-specific variant; all others work identically on both CLIs.

### Local development

```bash
claude --plugin-dir ./plugins/format-on-save
claude --plugin-dir ./plugins/permission-manager
```

## Repository Structure

```
agent-toolkit/
├── .claude-plugin/
│   └── marketplace.json          # Claude Code marketplace catalog
├── .github/plugin/
│   └── marketplace.json          # Copilot CLI marketplace catalog (hook variants)
├── plugins/                      # canonical plugin sources
│   ├── format-on-save/
│   ├── notify-on-stop/
│   ├── feature/
│   ├── image/
│   ├── markdown/
│   ├── convert-doc/
│   ├── frontmatter-query/
│   ├── jar-explore/
│   ├── maven-indexer/
│   ├── maven-tools/
│   └── permission-manager/
├── plugins-copilot/              # Copilot CLI variants (hook plugins only)
│   ├── format-on-save/
│   └── permission-manager/
└── utils/                        # shared scripts (symlinked into plugin scripts/)
```

### Plugin anatomy

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json               # name, version, description, author
├── skills/
│   └── <skill-name>/
│       └── SKILL.md              # skill definition with YAML frontmatter
├── hooks/
│   └── hooks.json                # hook event configuration
├── mcp.json                      # MCP server definitions
└── scripts/                      # helper scripts
```

## Dual-Marketplace Approach

Plugins without hooks work identically on both CLIs and are listed only in `.claude-plugin/marketplace.json`. Hook plugins that need Copilot CLI support get a variant under `plugins-copilot/` with a Copilot-format `hooks.json`. Shared directories (`scripts/`, `skills/`) are symlinked back to the canonical `plugins/` source.

```
plugins-copilot/<name>/
├── .claude-plugin/
│   └── plugin.json               # copy of canonical plugin.json
├── hooks/
│   └── hooks.json                # Copilot CLI format (camelCase events, flat array, version: 1)
└── scripts -> ../../plugins/<name>/scripts
```

The Copilot marketplace (`.github/plugin/marketplace.json`) points to the `-copilot` variants for hook plugins only.

## Cross-Compatibility Notes

Hook scripts normalize payload differences via `utils/hook-compat.sh`:

```bash
HOOK_INPUT=$(cat)
source "$(dirname "$0")/hook-compat.sh"
# Exports: HOOK_FORMAT, HOOK_TOOL_NAME, HOOK_COMMAND, HOOK_FILE_PATH, HOOK_EVENT_NAME
# hook_ask / hook_allow / hook_deny — output correct JSON per CLI
```

| Difference | Claude Code | Copilot CLI |
|-----------|-------------|-------------|
| Plugin root var | `${CLAUDE_PLUGIN_ROOT}` | `${COPILOT_PLUGIN_ROOT}` |
| Hook event names | PascalCase (`PreToolUse`) | camelCase (`preToolUse`) |
| Hook format | Nested `hooks` array, `command` key | Flat array, `bash` key, `version: 1` |
| Payload keys | `tool_name` / `tool_input` | `toolName` / `toolArgs` |

## License

MIT
