# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable CLI tools and Claude Code skills for development workflows. Each tool is a self-contained bash script paired with a skill definition that teaches Claude Code how and when to use it.

Project-level roadmap and investigation items live in `.claude/todo.md`.

## Structure

```
skills/
  <name>/                  ← one folder per skill (or platform variant)
    deploy.json            ← optional: skill deployment config (tracked)
    deploy.local.json      ← optional: user overrides (gitignored)
    bin/
      <script>             ← executable(s)
    <name>.md              ← skill definition(s)
hooks/
  <name>/                  ← one folder per hook
    deploy.json            ← optional: hook deployment config (tracked)
    deploy.local.json      ← optional: user overrides (gitignored)
    <script>.sh            ← hook script(s)
mcp/
  <name>/                  ← one folder per MCP server
    deploy.json            ← required: must contain "mcp" key with server config
    deploy.local.json      ← optional: user overrides (gitignored)
    setup.sh               ← optional: install prereqs (docker pull, compose up, etc.)
    docker-compose.yml     ← optional: if the server needs persistent containers
    README.md              ← optional: docs (not deployed)
permissions/
  <name>.json              ← permission group (e.g., git.json, docker.json)
  <name>.local.json        ← user override (gitignored)
deploy-rs/                 ← Rust deployment implementation
deploy                     ← convenience wrapper (calls deploy-rs binary)
deploy.json                ← optional: repo-wide deployment config (tracked)
deploy.local.json          ← optional: user overrides (gitignored)
CLAUDE.md
```

After deployment:

```
~/.claude/tools/<name>/          ← symlink to skills/<name>/ (scripts live here)
~/.claude/skills/<x>/SKILL.md   ← symlink to skill .md file (one dir per skill)
~/.claude/hooks/<name>/          ← symlink to hooks/<name>/ (hook scripts)
~/.local/bin/<script>            ← optional (--on-path), for direct human use
settings.json mcpServers         ← MCP server definitions (or .mcp.json with --project)
```

- `skills/<name>/` — groups a skill's script(s) and skill definition(s) together
- `hooks/<name>/` — groups a hook's script(s) together (deployed to `~/.claude/hooks/`)
- `permissions/<name>.json` — categorized permission groups (allow/deny entries for settings.json)
- `mcp/<name>/` — MCP server definitions and setup scripts (registered in settings.json)
- `deploy-rs/` — Rust deployer with CLI and TUI modes (see `deploy-rs/CLAUDE.md`)
- `deploy` — convenience wrapper script at the repo root

## Deployment

Run `./deploy` to symlink everything into place. Safe to re-run.

- **Scripts** always deploy to `~/.claude/tools/<tool-name>/` (the entire skill directory is symlinked)
- **Skills** (.md files) deploy to `~/.claude/skills/` (or `<project>/.claude/skills/` with `--project`)
- **Hooks** always deploy to `~/.claude/hooks/<hook-name>/` (global only, not affected by `--project`)
- **MCP servers** are registered in `settings.json` under `mcpServers` (or `<project>/.mcp.json` with `--project`)
- **Permissions** from `deploy.json` files are collected, deduplicated, and written to `~/.claude/settings.json` (or project settings with `--project`)
- **`--dry-run`** shows what would be done without making any changes
- **`--on-path`** optionally also symlinks scripts to `~/.local/bin/` for direct human use
- **`--skip-permissions`** skips settings.json permission management (escape hatch)
- **`--include tool1,tool2`** only deploy the listed items (comma-separated, names match `skills/`, `hooks/`, `mcp/` directories, or `permissions/` file stems)
- **`--exclude tool1,tool2`** deploy all items except the listed ones
- **`--teardown-mcp name1,name2`** teardown named MCP servers (runs `setup.sh --teardown` and removes config)
- `--include` and `--exclude` are mutually exclusive
- When `--project` is used, skills already deployed globally (`~/.claude/skills/`) are automatically skipped

Example workflows:

```bash
# Deploy a subset globally, then deploy the rest to a project
./deploy --include jar-explore,docker-pg-query
./deploy --exclude jar-explore,docker-pg-query --project /path/to/repo

# Teardown an MCP server
./deploy --teardown-mcp maven-tools
```

### Deployment config files

Tools, hooks, and MCP servers can be configured via JSON files instead of (or in addition to) CLI flags. Config files are optional — without them, behavior is identical to the flag-only defaults.

**Config file precedence** (lowest → highest):

| Priority | File | Tracked | Purpose |
|----------|------|---------|---------|
| 1 (lowest) | `deploy.json` (repo root) | Yes | Repo-wide defaults |
| 2 | `deploy.local.json` (repo root) | No | User's global overrides |
| 3 | `<type>/<name>/deploy.json` | Yes | Author defaults |
| 4 | `<type>/<name>/deploy.local.json` | No | User's per-item overrides |
| 5 (highest) | CLI flags | — | `--on-path`, `--project` |

Keys are merged bottom-up: a key in a higher-priority file replaces the same key from a lower one. Missing keys inherit from the next lower layer. `*.local.json` files are gitignored.

**Available keys (skills/hooks):**

```json
{
  "enabled": true,
  "scope": "global",
  "on_path": false,
  "dependencies": ["other-tool"],
  "permissions": {
    "allow": ["Bash(my-tool)", "Bash(my-tool *)"],
    "deny": []
  },
  "hooks_config": {
    "event": "PreToolUse",
    "matcher": "Bash",
    "command_script": "my-hook.sh",
    "async": false,
    "timeout": 60
  }
}
```

**Available keys (MCP servers):**

```json
{
  "enabled": true,
  "mcp": {
    "command": "docker",
    "args": ["run", "--rm", "-i", "some-image:tag"],
    "env": {}
  }
}
```

Or for HTTP-transport (URL-based) servers:

```json
{
  "enabled": true,
  "mcp": {
    "url": "https://mcp.example.com/mcp"
  }
}
```

- **`enabled`** (`true`/`false`) — Whether to deploy this item. `false` skips it entirely. Default: `true`.
- **`scope`** (`"global"` / `"project"`) — Where skills deploy. `"global"` → `~/.claude/skills/`, `"project"` → requires `--project` flag. Tools with `scope: "project"` are skipped when no `--project` flag is given. Default: `"global"`.
- **`on_path`** (`true`/`false`) — Symlink scripts to `~/.local/bin/`. Default: `false`.
- **`dependencies`** (`["tool-name", ...]`) — Other skills whose `skills/<name>/` directory should be symlinked to `~/.claude/tools/<name>/` when this skill deploys. Dependencies get their tool directory and permissions deployed, but NOT their skills (.md files). Use when a tool's scripts call another tool's scripts at runtime.
- **`permissions`** (`{allow: [...], deny: [...]}`) — Permission entries for `settings.json`. All entries from all config files are collected, deduplicated, sorted, and merged into the `permissions` section of `settings.json` using **append-missing** semantics — existing entries (including manually added ones) are preserved; only new entries are added. Entries are deduplicated and sorted.
- **`hooks_config`** (hooks only) — Registers a hook into `settings.json` `.hooks` using **append-missing** semantics — existing event+matcher pairs are preserved; only new ones are added. Manually added hooks survive re-deployment. Accepts a single object or an array of objects for multi-event hooks. Fields:
  - `event` (required) — Hook event name (e.g., `"PreToolUse"`, `"PostToolUse"`, `"Stop"`, `"UserPromptSubmit"`)
  - `matcher` (optional) — Tool matcher pattern (e.g., `"Bash"`, `"Edit|Write"`). Omit for events like `Stop` and `UserPromptSubmit` that aren't tool-specific.
  - `command_script` (required) — Script filename relative to the hook directory (resolved to `~/.claude/hooks/<hook-name>/<script>`)
  - `async` (optional, default `false`) — Run hook asynchronously
  - `timeout` (optional) — Timeout in seconds
- **`mcp`** (MCP servers only) — The server definition object written verbatim into `mcpServers.<name>`. Must contain `"command"` (stdio transport) or `"url"` (HTTP transport). Common fields: `command`, `args`, `env`, `url`.

**CLI flag interaction:**

- `--project PATH` overrides `scope` to `"project"` for all tools and provides the target path
- `--on-path` overrides `on_path` to `true` for all tools
- `--include`/`--exclude` filter before config is read

**Example** — make a tool project-scoped with PATH deployment (`skills/jar-explore/deploy.json`):

```json
{ "on_path": true, "scope": "project" }
```

**Example** — disable a tool locally without editing tracked files (`skills/image/deploy.local.json`):

```json
{ "enabled": false }
```

### Directory-specific guides

Each major directory has its own `CLAUDE.md` with detailed "how to add a new entry" instructions:

- **`skills/CLAUDE.md`** — Skill authoring: script conventions, `.md` frontmatter, directory layouts (single/multi/script-free), deploy.json options, templates
- **`mcp/CLAUDE.md`** — MCP servers: transport variants (stdio/HTTP/SSE), `setup.sh` template, `docker-compose.yml` patterns, existing server examples
- **`permissions/CLAUDE.md`** — Permission groups: file format, permission string syntax, `.local.json` overrides, deployment flow
- **`deploy-rs/CLAUDE.md`** — Rust deployer: build/run/test, project structure, key types, TUI architecture, conventions

## Testing

```bash
bash deploy-rs/test.sh                                # All tests (unit + integration)
bash deploy-rs/test.sh -- --test deploy_symlinks      # Filter by test module
bash deploy-rs/test.sh -- config::tests               # Filter by unit test path
```

See `deploy-rs/CLAUDE.md` for full testing details. Tests use `CLAUDE_CONFIG_DIR` pointed at a temp directory — they never touch real config.

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Tools should be safe for Claude Code hook auto-approval (read-only, temp cleanup)
