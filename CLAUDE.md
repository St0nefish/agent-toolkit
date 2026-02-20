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
deploy.py                  ← idempotent deployment script
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
- `deploy.py` — iterates `skills/*/`, `hooks/*/`, and `mcp/*/`, creates symlinks and registers config

## Deployment

Run `./deploy.py` to symlink everything into place. Safe to re-run.

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
./deploy.py --include jar-explore,docker-pg-query
./deploy.py --exclude jar-explore,docker-pg-query --project /path/to/repo

# Teardown an MCP server
./deploy.py --teardown-mcp maven-tools
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
- **`hooks_config`** (hooks only) — Registers a hook into `settings.json` `.hooks` using **append-missing** semantics — existing event+matcher pairs are preserved; only new ones are added. Manually added hooks survive re-deployment. Fields:
  - `event` (required) — Hook event name (e.g., `"PreToolUse"`, `"PostToolUse"`)
  - `matcher` (required) — Tool matcher pattern (e.g., `"Bash"`, `"Edit|Write"`)
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

### MCP server convention

Each MCP server lives in `mcp/<name>/` and requires:

1. **`deploy.json`** (required) — Must contain an `"mcp"` key with the server definition. Stdio transport:

   ```json
   {
     "mcp": {
       "command": "docker",
       "args": ["run", "--rm", "-i", "some-image:tag"],
       "env": {}
     }
   }
   ```

   HTTP transport (hosted servers):

   ```json
   {
     "mcp": {
       "url": "https://mcp.example.com/mcp"
     }
   }
   ```

   The `mcp` value is written verbatim into `mcpServers.<name>`.

2. **`setup.sh`** (optional) — Install prerequisites (docker pull, compose up, etc.):
   - `setup.sh` (no args) — install/setup
   - `setup.sh --teardown` — remove/cleanup
   - Exit 0 = success, non-zero = failure
   - deploy.py continues on failure (prints warning, skips config registration)

3. **`docker-compose.yml`** (optional) — For servers needing persistent containers

### Permission groups

Permission groups live as flat JSON files in `permissions/`. Each file contributes `allow`/`deny` entries to `settings.json`. They integrate with the existing profile and `--include`/`--exclude` systems.

**File format** (`permissions/<name>.json`):

```json
{
  "enabled": true,
  "permissions": {
    "allow": ["Bash(git status)", "Bash(git log)"]
  }
}
```

- `enabled` and `scope` keys work the same as for skills/hooks
- User overrides go in `<name>.local.json` (gitignored) — entries merge additively
- Profile overrides work via the `"permissions"` section (same as skills, hooks, mcp)
- `--include`/`--exclude` filter by group name (file stem, e.g., `git`, `bash-read`)

**Available groups**: `bash-read`, `system`, `git`, `docker`, `github`, `web`, `python`, `node`, `jvm`, `rust`

Permissions in `settings.json` are sorted into visual groups (bash-read, system, git, docker, etc.) for easier scanning.

### Skill naming

Every skill is deployed as its own directory containing a `SKILL.md` symlink. Two source layouts are supported:

**Legacy** — loose `.md` files in the tool folder:

- **One `.md` file**: `skills/catchup/catchup.md` → `~/.claude/skills/catchup/SKILL.md` → `/catchup`
- **Multiple `.md` files**: each gets its own skill — `skills/session/start.md` → `~/.claude/skills/session-start/SKILL.md` → `/session-start`

**Modern** — subdirectories with `SKILL.md`:

- `skills/session/start/SKILL.md` → `~/.claude/skills/session-start/SKILL.md` → `/session-start`
- `skills/session/end/SKILL.md` → `~/.claude/skills/session-end/SKILL.md` → `/session-end`

Both patterns produce the same deployment layout. If both are present in the same tool folder, the modern pattern takes priority. `README.md` files and `bin/` directories are excluded from skill detection.

## Skill Authoring Pattern

Every skill lives in `skills/<name>/` and consists of:

1. **`bin/<script>`** — The executable script
   - Shebang: `#!/usr/bin/env bash`
   - Strict mode: `set -euo pipefail`
   - Exit codes: 0 success, 1 bad usage, 2 file not found, 3 entry not found
   - Temp files in `/tmp` with `trap ... EXIT` cleanup
   - Errors to stderr, data to stdout
   - `usage()` function that prints help and exits 1
   - Subcommand dispatch via `case` statement

2. **`<name>.md`** — The skill definition
   - **Must have YAML frontmatter with a `description:` field** — this is what Claude sees in the system reminder at decision time, before it ever opens the skill body. Without it, Claude falls back to the H1 heading which is too terse to trigger reliable tool selection.
   - The description should follow this formula:
     1. **What it does** — action verbs matching how the user would phrase the task
     2. **REQUIRED / do NOT** — explicitly name the raw commands it replaces
     3. **Use when** — list concrete trigger scenarios
   - **Additional frontmatter fields:**
     - **`allowed-tools`** — Comma-separated list of tools the skill may use (e.g., `Bash, Read, Edit`). Restricts the skill's tool access when invoked, improving safety and predictability.
     - **`disable-model-invocation`** (`true`/`false`) — When `true`, the skill won't appear in the system prompt and can only be triggered via explicit `/command` invocation. Use for skills that are user-initiated workflows (e.g., session start/end) rather than tools Claude should autonomously reach for.
   - Example frontmatter:

     ```yaml
     ---
     description: >-
       Inspect, search, read, and decompile JAR files. REQUIRED for all JAR
       operations — do NOT use raw unzip, jar, javap, or find commands on JARs.
       Use when investigating dependencies, reading source JARs, decompiling
       classes, searching for classes/resources inside JARs, or locating JARs
       in the Gradle cache.
     allowed-tools: Bash, Read
     ---
     ```

   - Reference scripts using `~/.claude/tools/<tool-name>/bin/<script>` (not `./bin/`)
   - Body tells Claude Code how to use the tool: subcommands, exit codes, typical workflows, example commands
   - Notes on hook auto-approval safety (read-only tools can be auto-approved)

3. **`deploy.json`** (optional) — Deployment config
   - JSON with keys: `enabled`, `scope`, `on_path` (see "Deployment config files" above)
   - Tracked in git — use for tool author defaults (e.g., `{"on_path": true}`)
   - User overrides go in `deploy.local.json` (gitignored)

## Testing

Run all tests (pytest + bash) via the wrapper script:

```bash
bash tests/run-all.sh                       # All tests
bash tests/run-all.sh -v                    # Verbose pytest output
bash tests/run-all.sh -k perms             # Filter pytest by name
```

The wrapper is whitelisted in `.claude/settings.json` so Claude Code can run tests without prompting.

Individual test suites can also be run directly:

```bash
uv run pytest tests/                        # All pytest tests
bash tests/test-bash-safety-hook.sh          # Hook git classifier tests
bash tests/test-bash-safety-gradle.sh        # Hook gradle classifier tests
bash tests/test-format-on-save-hook.sh       # Format-on-save hook tests
```

Dependencies are managed via `pyproject.toml` dev group — `uv sync --group dev` installs them.

Deploy tests use `CLAUDE_CONFIG_DIR` (env var) pointed at a temp directory — they never touch real config.

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Tools should be safe for Claude Code hook auto-approval (read-only, temp cleanup)
