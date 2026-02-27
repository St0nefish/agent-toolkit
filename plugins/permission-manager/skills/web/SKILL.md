---
name: permission-web
description: >-
  Apply or manage WebFetch domain permissions in settings.json.
  Lists available permission groups, shows current status,
  and merges selected groups after user confirmation.
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# permission-web

Manage WebFetch domain permissions in `~/.claude/settings.json`.

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

Use `AskUserQuestion` with `multiSelect: true` to let the user choose which groups to apply. Use the status output to note which are already applied in each option's description.

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
