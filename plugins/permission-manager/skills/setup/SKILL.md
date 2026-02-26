---
name: permission-manager-setup
description: >-
  Manage categorized permission groups for Claude Code settings.json.
  Lists available groups, shows current status, and merges selected
  groups with deduplication and sorting.
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Permission Manager

Merge categorized permission groups into `~/.claude/settings.json`.

## Instructions

Follow these steps exactly:

### 1. Show current state

Run both commands and display the output to the user:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --list
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --status
```

### 2. Ask user to select groups

Use `AskUserQuestion` with `multiSelect: true` to let the user choose which groups to apply. Include all 10 groups as options. Use the status output to note which are already applied in each option's description.

The groups are:
- **bash-read** — Read-only shell commands (cat, grep, find, etc.)
- **docker** — Read-only Docker inspection commands
- **git** — Read-only git commands (log, diff, status, etc.)
- **github** — Read-only GitHub CLI commands
- **jvm** — JVM toolchain commands (gradle, java, javap, etc.)
- **node** — Node.js toolchain commands (npm, yarn, pnpm, etc.)
- **python** — Python toolchain commands (pip, uv, pyenv, etc.)
- **rust** — Rust toolchain commands (cargo, rustup, etc.)
- **system** — System info commands (ps, df, uptime, etc.)
- **web** — Allowed WebFetch domains

### 3. Dry run

Run the merge script with `--dry-run` and the selected groups to show what would change:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --dry-run <selected-groups>
```

Show the output to the user.

### 4. Confirm and apply

Ask the user to confirm. If they approve, run the merge without `--dry-run`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh <selected-groups>
```

Report the result.
