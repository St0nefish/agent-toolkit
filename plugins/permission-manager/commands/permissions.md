---
description: "Permission management — commands, setup, web"
argument-hint: "[action]"
allowed-tools: Bash, Read, AskUserQuestion
disable-model-invocation: true
---

# Permissions

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `commands`, `setup`, `web`. Usage: `/permissions [action]`)

---

## commands

Manage custom command patterns for the bash-safety hook.

Custom patterns are glob strings matched against each command segment.
Commands matching a pattern are automatically allowed without prompting.

### Config files

| Scope | File | Use case |
|-------|------|----------|
| Global | `~/.claude/command-permissions.json` | Session tools, pandoc, personal prefs |
| Project | `.claude/command-permissions.json` | Test scripts, project build tools |

### Instructions

Follow these steps exactly:

#### 1. Show current patterns

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh list
```

Display the output to the user.

#### 2. Ask what the user wants to do

Use `AskUserQuestion` to ask:

- **Add a pattern** — prompt for the glob pattern and scope (global or project)
- **Remove a pattern** — prompt for which pattern to remove and its scope
- **Done** — exit

#### 3. Execute the action

To add:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh add --scope <scope> '<pattern>'
```

To remove:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh remove --scope <scope> '<pattern>'
```

#### 4. Show updated state and repeat

After each action, re-run `list` to show the updated patterns, then go back to step 2.

---

## setup

Install the required dependencies for the bash-safety hook.

### Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-deps.sh
```

Report the result to the user. If installation fails, show the manual install links from the script output.

---

## web

Manage WebFetch domain permissions in `~/.claude/settings.json`.

### Instructions

Follow these steps exactly:

#### 1. Show current state

Run both commands and display the output to the user:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --list
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --status
```

#### 2. Ask user to select groups

Use `AskUserQuestion` with `multiSelect: true` to let the user choose which groups to apply. Use the status output to note which are already applied in each option's description.

#### 3. Dry run

Run the merge script with `--dry-run` and the selected groups to show what would change:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --dry-run <selected-groups>
```

Show the output to the user.

#### 4. Confirm and apply

Ask the user to confirm. If they approve, run the merge without `--dry-run`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh <selected-groups>
```

Report the result.
