---
name: permission-commands
description: >-
  Add, remove, or list custom command patterns that auto-allow
  Bash commands matching glob patterns. Manages patterns at
  global (~/.claude/command-permissions.json) and project
  (.claude/command-permissions.json) scopes.
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# permission-commands

Manage custom command patterns for the bash-safety hook.

Custom patterns are glob strings matched against each command segment.
Commands matching a pattern are automatically allowed without prompting.

## Config files

| Scope | File | Use case |
|-------|------|----------|
| Global | `~/.claude/command-permissions.json` | Session tools, pandoc, personal prefs |
| Project | `.claude/command-permissions.json` | Test scripts, project build tools |

## Instructions

Follow these steps exactly:

### 1. Show current patterns

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh list
```

Display the output to the user.

### 2. Ask what the user wants to do

Use `AskUserQuestion` to ask:
- **Add a pattern** — prompt for the glob pattern and scope (global or project)
- **Remove a pattern** — prompt for which pattern to remove and its scope
- **Done** — exit

### 3. Execute the action

To add:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh add --scope <scope> '<pattern>'
```

To remove:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh remove --scope <scope> '<pattern>'
```

### 4. Show updated state and repeat

After each action, re-run `list` to show the updated patterns, then go back to step 2.
