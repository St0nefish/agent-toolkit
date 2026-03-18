# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable Claude Code plugins for development workflows, distributed via the Claude Code plugin marketplace. Each plugin is independently installable and contains commands, skills, hooks, MCP servers, or scripts.

## Structure

```text
agent-toolkit/                              # marketplace repo
├── .claude-plugin/
│   └── marketplace.json                     # Claude Code marketplace catalog
├── .github/plugin/
│   └── marketplace.json                     # Copilot CLI marketplace catalog
├── plugins-claude/                          # canonical plugin sources
│   ├── format-on-save/                      # hook: auto-format after Edit/Write
│   ├── notify-on-stop/                      # hook: desktop notification on completion
│   ├── session/                             # commands + skills: work session management
│   ├── git-cli/                             # skill: GitHub/Gitea CLI wrapper
│   ├── image/                               # skills: clipboard paste + screenshot
│   ├── markdown/                            # command: lint, format, setup
│   ├── convert-doc/                         # skill: pandoc document conversion
│   ├── frontmatter-query/                   # skill: YAML frontmatter queries
│   ├── jar-explore/                         # skill: JAR content inspection
│   ├── maven-indexer/                       # MCP + command: class search/decompile
│   ├── maven-tools/                         # MCP + command: Maven Central intelligence
│   └── permission-manager/                  # hook + command: Bash safety classifier
├── plugins-copilot/                         # Copilot CLI variants (all plugins)
│   ├── format-on-save/                      # symlinks + Copilot-format hooks.json
│   ├── permission-manager/                  # symlinks + Copilot-format hooks.json
│   └── <other-plugins>/                     # mirrored variants (mostly using symlinks)
└── utils/                                   # shared scripts (symlinked into plugin scripts/)
    ├── hook-compat.sh                       # hook payload normalizer
    └── git-cli                              # GitHub/Gitea CLI wrapper
```

Each plugin follows this internal layout:

```text
plugins-claude/<name>/
├── .claude-plugin/
│   └── plugin.json          # required: name, version, description
├── commands/                # user-invocable slash commands (/plugin:command)
│   └── <command>.md         # command definition with YAML frontmatter
├── skills/                  # auto-discovered skill directories
│   └── <skill-name>/
│       └── SKILL.md         # skill definition with YAML frontmatter
├── hooks/
│   └── hooks.json           # hook event configuration
├── mcp.json                 # MCP server definitions (declared in plugin.json)
└── scripts/                 # helper scripts (referenced via ${CLAUDE_PLUGIN_ROOT})
```

## Plugin Components

| Type | Location | Format | Discovery |
|------|----------|--------|-----------|
| Commands | `commands/<name>.md` | Markdown with YAML frontmatter | Auto-discovered, user-invocable via `/plugin:command` |
| Skills | `skills/<name>/SKILL.md` | Markdown with YAML frontmatter | Auto-discovered, model-triggered |
| Hooks | `hooks/hooks.json` | JSON with `{hooks: {Event: [...]}}` wrapper | Auto-registered |
| MCP servers | `mcp.json` | JSON with `{mcpServers: {...}}` | Declared in `plugin.json` via `mcpServers` field |
| Scripts | `scripts/<name>` | Bash/Python executables | Referenced from commands/skills/hooks |

## Commands vs Skills

Commands and skills both define behavior but differ in visibility:

- **Commands** (`commands/*.md`) — appear in `/` autocomplete as `/plugin:command`. User-initiated.
- **Skills** (`skills/*/SKILL.md` with `user-invocable: false`) — invisible in autocomplete. The model triggers them automatically when context matches the skill's `description`.

Use commands for actions the user explicitly invokes (`/session:start`, `/session:end`). Use skills for capabilities the model should reach for on its own (summarizing changes, posting to issues, checking status).

A plugin can have both — the `session` plugin exposes 8 commands for explicit actions while keeping 3 skills (catchup, checkpoint, summarize) as model-triggered helpers.

## Shared Scripts

`utils/` holds scripts used by multiple plugins. Symlink them into each plugin's `scripts/` directory with a relative path:

```bash
# From plugins-claude/<name>/scripts/
ln -s ../../../utils/git-cli git-cli
```

Both CLIs dereference symlinks on install, so each installed plugin gets a standalone copy with no cross-plugin runtime dependency. Scripts reference co-located siblings via `$(dirname "$0")/sibling` — this works whether the script is a real file or a resolved symlink.

## Path References

Use `${CLAUDE_PLUGIN_ROOT}` for all intra-plugin path references:

- In command/skill content: `${CLAUDE_PLUGIN_ROOT}/scripts/my-tool` (resolved at load time)
- In hook commands: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh` (resolved at execution)
- In MCP configs: `${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` (resolved at registration)

Never use hardcoded paths like `~/.claude/tools/...`.

## Installation

Install individual plugins from the marketplace:

```bash
claude plugin install agent-toolkit/format-on-save
claude plugin install agent-toolkit/permission-manager
```

Or test locally during development:

```bash
claude --plugin-dir ./plugins-claude/permission-manager
```

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Use kebab-case for all directory and file names
- Skills that are model-triggered (not user-initiated) set `user-invocable: false`
- Scripts reference siblings via `$(dirname "$0")` for co-located files
- Slash command syntax uses colons: `/plugin:command` (not `/plugin command`)
- **Always bump the plugin version** in both `plugins-claude/<name>/.claude-plugin/plugin.json` and `plugins-copilot/<name>/.claude-plugin/plugin.json` when making any changes to a plugin. A patch version bump (e.g. `3.1.0` → `3.1.1`) is sufficient unless the change is a new feature (minor) or breaking (major). Installed plugins won't update without a version change.

## Workflow

This is a GitHub-hosted repository. Use `gh` for all GitHub operations (PRs, issues, CI checks).

### Validation

CI runs four independent checks. Run all locally before pushing:

```bash
bash test.sh                                   # plugin tests
bash .github/scripts/validate-plugins.sh       # plugin structure
bash .github/scripts/validate-frontmatter.sh   # command/skill frontmatter
rumdl .                                        # markdown linting
```

Run a single test suite directly:

```bash
bash tests/permission-manager/test-*.sh
```

### Branching and commits

The `master` branch is protected — never commit directly to it. For all changes:

1. Ensure you're branching from the latest `master`:

   ```bash
   git checkout master && git pull
   ```

2. Create a feature branch with a descriptive name (e.g. `feat/tea-classifier`, `bug/redirect-op-codes`)
3. Commit with a structured message:
   - **Title line**: concise summary in imperative mood (e.g. `feat: add tea CLI classifier to permission-manager`)
   - **Body** (optional, for larger changes): a short paragraph explaining the motivation or context
   - **Bullet list**: specific changes made
4. Push the branch and open a PR via `gh pr create`
5. Monitor the GitHub Actions run (`gh run list`, `gh run view`) — fix any failures and push follow-up commits
6. **Do not manually merge PRs.** A CI bot (`st0nefish-ci`) automatically enables auto-merge (squash) on new PRs. Once CI passes, the PR merges on its own.
7. After the PR merges, check out `master` and pull to stay current:

   ```bash
   git checkout master && git pull
   ```

## Copilot CLI Compatibility

Both Claude Code and Copilot CLI recognize the same plugin format (`.claude-plugin/`, `commands/`, `skills/`, `hooks/`). However, Claude Code strictly validates hook event keys, rejecting the camelCase format Copilot CLI uses. The two CLIs also use different marketplace discovery paths:

| | Claude Code | Copilot CLI |
|---|---|---|
| Marketplace | `.claude-plugin/marketplace.json` | `.github/plugin/marketplace.json` |
| Hook events | PascalCase (`PreToolUse`) | camelCase (`preToolUse`) |
| Hook format | Nested `hooks` array, `command` key | Flat array, `bash` key, `version: 1` |
| Plugin root var | `${CLAUDE_PLUGIN_ROOT}` | `${COPILOT_PLUGIN_ROOT}` |

**Dual-marketplace approach** — Both marketplaces list all plugins. Copilot CLI uses `plugins-copilot/` variants so hook-enabled plugins can provide a Copilot-format `hooks.json`, while shared directories (scripts, skills, groups, etc.) are symlinked back to the canonical `plugins-claude/` source. For `maven-indexer` and `maven-tools`, `commands/` is copied in `plugins-copilot/` to keep Copilot-specific command frontmatter:

```text
plugins-copilot/<name>/
├── .claude-plugin/
│   └── plugin.json          # copy of canonical plugin.json
├── hooks/
│   └── hooks.json           # Copilot CLI format (camelCase, flat, version:1)
├── commands/                # copied (not symlinked) when frontmatter differs
├── scripts -> ../../plugins-claude/<name>/scripts
├── skills -> ../../plugins-claude/<name>/skills
└── <other-dirs> -> ../../plugins-claude/<name>/<other-dirs>
```

The Copilot CLI marketplace (`.github/plugin/marketplace.json`) points to the `-copilot` variants for all plugins.

**Hook script input** — Claude Code sends `tool_name`/`tool_input` (snake_case); Copilot CLI sends `toolName`/`toolArgs` (camelCase, args as JSON string). Source `hook-compat.sh` to normalize:

```bash
HOOK_INPUT=$(cat)
source "$(dirname "$0")/hook-compat.sh"
# Exports: HOOK_FORMAT, HOOK_TOOL_NAME, HOOK_COMMAND, HOOK_FILE_PATH, HOOK_EVENT_NAME
# hook_ask "reason" / hook_allow "reason" — output correct JSON per CLI
```
