# Agent Toolkit

A collection of Claude Code plugins and GitHub Copilot CLI plugins/extensions for development workflows. Plugins are marketplace-installable; extensions can live in-repo or in the user's Copilot config.

## Plugin Catalogue

### Productivity

| Plugin | Type | Description |
|--------|------|-------------|
| [`format-on-save`](plugins-claude/format-on-save/) | Hook | Auto-formats files after Edit/Write using language-appropriate formatters (`shfmt`, `prettier`, `markdownlint`, `google-java-format`, `ktlint`, `rustfmt`, `ruff`) |
| [`notify-on-stop`](plugins-claude/notify-on-stop/) | Hook | Desktop notification when Claude finishes a long-running task (configurable threshold) |
| [`session`](plugins-claude/session/) | Skills | Work session management — start, end, checkpoint, handoff, resume, issue, reset, orchestrate, plus a model-triggered summarize skill |
| [`image`](plugins-claude/image/) | Skills | Clipboard paste and screenshot capture for macOS, WSL, and Linux |
| [`markdown`](plugins-claude/markdown/) | Skills | Markdown linting and formatting — check, format, setup |
| [`convert-doc`](plugins-claude/convert-doc/) | Skill | Convert documents to/from markdown using pandoc (DOCX, HTML, RST, EPUB, ODT, RTF, LaTeX) |
| [`elevated-edit`](plugins-claude/elevated-edit/) | Skill | Pull/edit/push workflow for remote or privileged files — bridges SSH and sudo boundaries using rsync |
| [`statusline`](plugins-claude/statusline/) | Skill | Configurable status line for Claude Code — git status, model, context, API usage, cost segments with ANSI colors (Claude only) |

### Development

| Plugin | Type | Description |
|--------|------|-------------|
| [`agentic-ide`](plugins-claude/agentic-ide/) | Skills + Agent | IDE-grade code intelligence — Serena (LSP symbol nav/refactor), ast-grep (AST search/rewrite), Semgrep (security & dataflow), plus a context-isolated explorer agent |
| [`git-tools`](plugins-claude/git-tools/) | Skills | GitHub and Gitea tooling — unified CLI wrapper plus a `ship` orchestrator for the full branch/commit/push/PR/watch/cleanup lifecycle |
| [`java-toolkit`](plugins-claude/java-toolkit/) | MCP + Skills | Java/JVM tooling — Maven Central intelligence, class search/decompilation (Docker Compose), plus a jar-explore skill for raw JAR content inspection |
| [`kb-capture`](plugins-claude/kb-capture/) | Skills | Research-to-document automation — capture findings as schema-valid markdown with frontmatter |
| [`session-history-analyzer`](plugins-claude/session-history-analyzer/) | Skills | Analyze Claude Code session history for workflow patterns, friction hotspots, and automation candidates |

### Security

| Plugin | Type | Description |
|--------|------|-------------|
| [`permission-manager`](plugins-claude/permission-manager/) | Hook + Skills | Bash command gating with shfmt-based compound parsing, extensible custom patterns, and WebFetch domain management |

### Gaming

| Plugin | Type | Description |
|--------|------|-------------|
| [`stl-game-config`](plugins-claude/stl-game-config/) | Skills | Configure Steam games via SteamTinkerLaunch with automated system detection and template-based configuration |

### Copilot-only

| Plugin | Type | Description |
|--------|------|-------------|
| [`sf-code-review`](plugins-copilot/sf-code-review/) | Commands + Skill | Chunked cross-family code review orchestration for Copilot CLI — dual Sonnet 4.6 + GPT-5.4 review with targeted Opus 4.6 adjudication |

### Copilot extensions

| Extension | Type | Description |
|-----------|------|-------------|
| [`git-worktree`](copilot-extensions/git-worktree/) | User-level extension source | Native worktree tools for Copilot CLI — status, create, remove, and parallel-work suggestions |

## Installation

### Claude Code

```bash
claude plugin install <owner/repo>/plugin-name
```

Example:

```bash
claude plugin install St0nefish/agent-toolkit/format-on-save
claude plugin install St0nefish/agent-toolkit/permission-manager
```

### GitHub Copilot CLI

```bash
copilot plugin install <owner/repo>/plugin-name
```

Hook plugins have a Copilot-specific variant; all others work identically on both CLIs.

This repo keeps the `git-worktree` extension source under `copilot-extensions/git-worktree/` and does **not** auto-load it as a project extension.

To install or update the same extension for all repos:

```bash
curl -fsSL https://raw.githubusercontent.com/St0nefish/agent-toolkit/master/scripts/install-copilot-git-worktree.sh | bash
```

The installer also seeds Copilot's persisted tool approvals for the current repo so `user:git-worktree` and its `sf_git_worktree_*` tools stop prompting repeatedly.
It also installs `~/.local/bin/copilot-git-worktree-allow` so you can seed the same approvals later from any repo without cloning `agent-toolkit`.

### Local development

```bash
claude --plugin-dir ./plugins-claude/format-on-save
claude --plugin-dir ./plugins-claude/permission-manager
```

## Repository Structure

```text
agent-toolkit/
├── .claude-plugin/
│   └── marketplace.json          # Claude Code marketplace catalog
├── .github/plugin/
│   └── marketplace.json          # Copilot CLI marketplace catalog (hook variants)
├── copilot-extensions/
│   └── git-worktree/             # Copilot CLI user-level extension source
├── plugins-claude/               # canonical plugin sources
│   ├── agentic-ide/
│   ├── convert-doc/
│   ├── elevated-edit/
│   ├── format-on-save/
│   ├── git-tools/
│   ├── image/
│   ├── java-toolkit/
│   ├── kb-capture/
│   ├── markdown/
│   ├── notify-on-stop/
│   ├── permission-manager/
│   ├── session/
│   ├── session-history-analyzer/
│   ├── statusline/
│   └── stl-game-config/
├── plugins-copilot/              # Copilot CLI variants
│   ├── <plugin>/commands/        # Copilot-only slash-command surface (real directory)
│   ├── <plugin>/hooks/           # Copilot-format hooks.json for hook plugins
│   └── <plugin>/<other-dirs>     # symlinked back to plugins-claude/<plugin>/...
├── scripts/
│   └── install-copilot-git-worktree.sh  # user-level install/update helper for the Copilot extension
└── utils/                        # shared scripts (vendored into plugin scripts/)
```

### Plugin anatomy

```text
plugins-claude/<name>/
├── .claude-plugin/
│   └── plugin.json               # name, version, description, author
├── skills/                       # all user/model-invocable surface — see invocation flags
│   └── <skill-name>/
│       └── SKILL.md              # skill definition with YAML frontmatter
├── hooks/
│   └── hooks.json                # hook event configuration
├── mcp.json                      # MCP server definitions
└── scripts/                      # helper scripts
```

## Dual-Marketplace Approach

Both marketplaces list nearly all plugins. Copilot CLI entries point to `plugins-copilot/` variants so hook-enabled plugins can use Copilot-format `hooks.json`, while shared directories (`scripts/`, `skills/`, etc.) are symlinked back to canonical `plugins-claude/` sources. The `commands/` directory only exists in `plugins-copilot/` — Copilot CLI requires it for slash commands, while Claude uses skills with the `disable-model-invocation: true` frontmatter flag instead. User-level Copilot extensions can live under `~/.copilot/extensions/`; this repo keeps their canonical source under `copilot-extensions/`.

A few surfaces are intentionally CLI-specific: `statusline` is Claude-only (no Copilot equivalent surface), `sf-code-review` is a Copilot-only plugin, and `git-worktree` is now a Copilot-only extension.

```text
plugins-copilot/<name>/
├── .claude-plugin/
│   └── plugin.json               # copy of canonical plugin.json
├── hooks/
│   └── hooks.json                # Copilot CLI format (camelCase events, flat array, version: 1)
└── scripts -> ../../plugins-claude/<name>/scripts
```

The Copilot marketplace (`.github/plugin/marketplace.json`) points to the `-copilot` variants for marketplace plugins only; `git-worktree` is intentionally extension-backed instead.

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
