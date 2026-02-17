# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable CLI tools and Claude Code skills for development workflows. Each tool is a self-contained bash script paired with a skill definition that teaches Claude Code how and when to use it.

## Structure

```
conditionals/
  is-wsl.sh                ← exit 0 if WSL, exit 1 otherwise
  is-macos.sh              ← exit 0 if macOS, exit 1 otherwise
tools/
  <name>/                  ← one folder per tool (or platform variant)
    condition.sh           ← optional: exit 0 to deploy, non-zero to skip
    bin/
      <script>             ← executable(s)
    <name>.md              ← skill definition(s)
deploy.sh                  ← idempotent deployment script
CLAUDE.md
```

After deployment:

```
~/.claude/tools/<name>/    ← symlink to tools/<name>/ (scripts live here)
~/.claude/commands/<x>.md  ← symlink to individual skill .md files
~/.local/bin/<script>      ← optional (--on-path), for direct human use
```

- `conditionals/` — reusable deployment gate scripts (see below)
- `tools/<name>/` — groups a tool's script(s) and skill definition(s) together
- `deploy.sh` — iterates `tools/*/`, checks conditions, creates symlinks

## Deployment

Run `./deploy.sh` to symlink everything into place. Safe to re-run.

- **Scripts** always deploy to `~/.claude/tools/<tool-name>/` (the entire tool directory is symlinked)
- **Skills** (.md files) deploy to `~/.claude/commands/` (or `<project>/.claude/commands/` with `--project`)
- **`--on-path`** optionally also symlinks scripts to `~/.local/bin/` for direct human use
- **`--include tool1,tool2`** only deploy the listed tools (comma-separated, names match `tools/` directories)
- **`--exclude tool1,tool2`** deploy all tools except the listed ones
- `--include` and `--exclude` are mutually exclusive
- When `--project` is used, skills already deployed globally (`~/.claude/commands/`) are automatically skipped

Example workflows:

```bash
# Deploy a subset globally, then deploy the rest to a project
./deploy.sh --include jar-explore,docker-pg-query
./deploy.sh --exclude jar-explore,docker-pg-query --project /path/to/repo
```

### Conditional deployment

If `tools/<name>/condition.sh` exists and is executable, `deploy.sh` runs it. Exit 0 means deploy; non-zero means skip. Use this for:

- **OS checks**: `[[ "$(uname -s)" == "Darwin" ]]`
- **Command existence**: `command -v powershell.exe >/dev/null 2>&1`
- **Any prerequisite**: environment variables, file existence, etc.

Platform variants use separate folders (e.g., `paste-image-wsl/`, `paste-image-macos/`) with the same `.md` filename (`paste-image.md`). Only one condition passes per machine, so the deployed command is always `/paste-image` with no collision.

### Skill naming

- **One `.md` file** in a tool folder: the `.md` file is symlinked to `~/.claude/commands/<md-filename>` — the command name derives from the `.md` filename (e.g., `jar-explore.md` → `/jar-explore`)
- **Multiple `.md` files**: a subdirectory `~/.claude/commands/<tool-name>/` is created and each `.md` file is symlinked inside — commands become `/<tool-name>:<md-name>`
- `README.md` files are excluded from skill deployment

## Tool/Skill Authoring Pattern

Every tool lives in `tools/<name>/` and consists of:

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
   - Example frontmatter:
     ```yaml
     ---
     description: >-
       Inspect, search, read, and decompile JAR files. REQUIRED for all JAR
       operations — do NOT use raw unzip, jar, javap, or find commands on JARs.
       Use when investigating dependencies, reading source JARs, decompiling
       classes, searching for classes/resources inside JARs, or locating JARs
       in the Gradle cache.
     ---
     ```
   - Reference scripts using `~/.claude/tools/<tool-name>/bin/<script>` (not `./bin/`)
   - Body tells Claude Code how to use the tool: subcommands, exit codes, typical workflows, example commands
   - Notes on hook auto-approval safety (read-only tools can be auto-approved)

3. **`condition.sh`** (optional) — Deployment gate
   - Must be executable (`chmod +x`)
   - Exit 0 = deploy, non-zero = skip
   - Keep it simple: one-liner checks preferred
   - **Prefer symlink** to a reusable script in `conditionals/` for single-condition tools (e.g., `condition.sh -> ../../conditionals/is-wsl.sh`)
   - For compound conditions, write a real `condition.sh` that chains calls: `../../conditionals/is-wsl.sh && ../../conditionals/has-cmd.sh powershell.exe`

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Tools should be safe for Claude Code hook auto-approval (read-only, temp cleanup)
