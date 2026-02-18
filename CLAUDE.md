# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable CLI tools and Claude Code skills for development workflows. Each tool is a self-contained bash script paired with a skill definition that teaches Claude Code how and when to use it.

## Structure

```
conditionals/
  is-wsl.sh                ← exit 0 if WSL, exit 1 otherwise
  is-macos.sh              ← exit 0 if macOS, exit 1 otherwise
skills/
  <name>/                  ← one folder per skill (or platform variant)
    condition.sh           ← optional: exit 0 to deploy, non-zero to skip
    deploy.json            ← optional: skill deployment config (tracked)
    deploy.local.json      ← optional: user overrides (gitignored)
    bin/
      <script>             ← executable(s)
    <name>.md              ← skill definition(s)
hooks/
  <name>/                  ← one folder per hook
    condition.sh           ← optional: exit 0 to deploy, non-zero to skip
    deploy.json            ← optional: hook deployment config (tracked)
    deploy.local.json      ← optional: user overrides (gitignored)
    <script>.sh            ← hook script(s)
deploy.py                  ← idempotent deployment script
deploy.json                ← optional: repo-wide deployment config (tracked)
deploy.local.json          ← optional: user overrides (gitignored)
CLAUDE.md
```

After deployment:

```
~/.claude/tools/<name>/    ← symlink to skills/<name>/ (scripts live here)
~/.claude/commands/<x>.md  ← symlink to individual skill .md files
~/.claude/hooks/<name>/    ← symlink to hooks/<name>/ (hook scripts)
~/.local/bin/<script>      ← optional (--on-path), for direct human use
```

- `conditionals/` — reusable deployment gate scripts (see below)
- `skills/<name>/` — groups a skill's script(s) and skill definition(s) together
- `hooks/<name>/` — groups a hook's script(s) together (deployed to `~/.claude/hooks/`)
- `deploy.py` — iterates `skills/*/` and `hooks/*/`, checks conditions, creates symlinks

## Deployment

Run `./deploy.py` to symlink everything into place. Safe to re-run.

- **Scripts** always deploy to `~/.claude/tools/<tool-name>/` (the entire skill directory is symlinked)
- **Skills** (.md files) deploy to `~/.claude/commands/` (or `<project>/.claude/commands/` with `--project`). We use `commands/` rather than `skills/` because only `commands/` supports colon-namespaced commands (e.g., `/session:start`) via subdirectory symlinks.
- **Hooks** always deploy to `~/.claude/hooks/<hook-name>/` (global only, not affected by `--project`)
- **Permissions** from `deploy.json` files are collected, deduplicated, and written to `~/.claude/settings.json` (or project settings with `--project`)
- **`--dry-run`** shows what would be done without making any changes
- **`--on-path`** optionally also symlinks scripts to `~/.local/bin/` for direct human use
- **`--skip-permissions`** skips settings.json permission management (escape hatch)
- **`--include tool1,tool2`** only deploy the listed tools (comma-separated, names match `skills/` directories)
- **`--exclude tool1,tool2`** deploy all tools except the listed ones
- `--include` and `--exclude` are mutually exclusive
- When `--project` is used, skills already deployed globally (`~/.claude/commands/`) are automatically skipped

Example workflows:

```bash
# Deploy a subset globally, then deploy the rest to a project
./deploy.py --include jar-explore,docker-pg-query
./deploy.py --exclude jar-explore,docker-pg-query --project /path/to/repo
```

### Conditional deployment

If `skills/<name>/condition.sh` exists and is executable, `deploy.py` runs it. Exit 0 means deploy; non-zero means skip. Use this for:

- **OS checks**: `[[ "$(uname -s)" == "Darwin" ]]`
- **Command existence**: `command -v powershell.exe >/dev/null 2>&1`
- **Any prerequisite**: environment variables, file existence, etc.

Platform-aware tools (e.g., `image/`) detect the platform at runtime via `uname -s` and `/proc/version`. The multi-`.md` convention gives colon-namespaced commands (e.g., `/image:screenshot`, `/image:paste`).

### Deployment config files

Tools and hooks can be configured via JSON files instead of (or in addition to) CLI flags. Config files are optional — without them, behavior is identical to the flag-only defaults.

**Config file precedence** (lowest → highest):

| Priority | File | Tracked | Purpose |
|----------|------|---------|---------|
| 1 (lowest) | `deploy.json` (repo root) | Yes | Repo-wide defaults |
| 2 | `deploy.local.json` (repo root) | No | User's global overrides |
| 3 | `skills/<name>/deploy.json` | Yes | Skill author defaults |
| 4 | `skills/<name>/deploy.local.json` | No | User's per-skill overrides |
| 5 (highest) | CLI flags | — | `--on-path`, `--project` |

Keys are merged bottom-up: a key in a higher-priority file replaces the same key from a lower one. Missing keys inherit from the next lower layer. `*.local.json` files are gitignored.

**Available keys:**

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

- **`enabled`** (`true`/`false`) — Whether to deploy this tool. `false` skips it entirely. Default: `true`.
- **`scope`** (`"global"` / `"project"`) — Where skills deploy. `"global"` → `~/.claude/commands/`, `"project"` → requires `--project` flag. Tools with `scope: "project"` are skipped when no `--project` flag is given. Default: `"global"`.
- **`on_path`** (`true`/`false`) — Symlink scripts to `~/.local/bin/`. Default: `false`.
- **`dependencies`** (`["tool-name", ...]`) — Other skills whose `skills/<name>/` directory should be symlinked to `~/.claude/tools/<name>/` when this skill deploys. Dependencies get their tool directory and permissions deployed, but NOT their skills (.md files). Use when a tool's scripts call another tool's scripts at runtime.
- **`permissions`** (`{allow: [...], deny: [...]}`) — Permission entries for `settings.json`. All entries from all config files are collected, deduplicated, sorted, and merged into the `permissions` section of `settings.json` using **append-missing** semantics — existing entries (including manually added ones) are preserved; only new entries are added. Entries are deduplicated and sorted.
- **`hooks_config`** (hooks only) — Registers a hook into `settings.json` `.hooks` using **append-missing** semantics — existing event+matcher pairs are preserved; only new ones are added. Manually added hooks survive re-deployment. Fields:
  - `event` (required) — Hook event name (e.g., `"PreToolUse"`, `"PostToolUse"`)
  - `matcher` (required) — Tool matcher pattern (e.g., `"Bash"`, `"Edit|Write"`)
  - `command_script` (required) — Script filename relative to the hook directory (resolved to `~/.claude/hooks/<hook-name>/<script>`)
  - `async` (optional, default `false`) — Run hook asynchronously
  - `timeout` (optional) — Timeout in seconds

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

### Skill naming

- **One `.md` file** in a tool folder: the `.md` file is symlinked to `~/.claude/commands/<md-filename>` — the command name derives from the `.md` filename (e.g., `jar-explore.md` → `/jar-explore`)
- **Multiple `.md` files**: a subdirectory `~/.claude/commands/<tool-name>/` is created and each `.md` file is symlinked inside — commands become `/<tool-name>:<md-name>`
- `README.md` files are excluded from skill deployment

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

3. **`condition.sh`** (optional) — Deployment gate
   - Must be executable (`chmod +x`)
   - Exit 0 = deploy, non-zero = skip
   - Keep it simple: one-liner checks preferred
   - **Prefer symlink** to a reusable script in `conditionals/` for single-condition skills (e.g., `condition.sh -> ../../conditionals/is-wsl.sh`)
   - For compound conditions, write a real `condition.sh` that chains calls: `../../conditionals/is-wsl.sh && ../../conditionals/has-cmd.sh powershell.exe`

4. **`deploy.json`** (optional) — Deployment config
   - JSON with keys: `enabled`, `scope`, `on_path` (see "Deployment config files" above)
   - Tracked in git — use for tool author defaults (e.g., `{"on_path": true}`)
   - User overrides go in `deploy.local.json` (gitignored)

## Testing

Deploy tests are pytest-based. Hook tests are plain bash scripts. Run from repo root:

```bash
uv run --with pytest pytest tests/          # All deploy.py tests
bash tests/test-bash-safety-hook.sh          # Hook git classifier tests
bash tests/test-bash-safety-gradle.sh        # Hook gradle classifier tests
bash tests/test-format-on-save-hook.sh       # Format-on-save hook tests
```

Deploy tests use `CLAUDE_CONFIG_DIR` (env var) pointed at a temp directory — they never touch real config.

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Tools should be safe for Claude Code hook auto-approval (read-only, temp cleanup)
