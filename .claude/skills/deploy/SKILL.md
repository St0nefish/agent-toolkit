---
description: >-
  Interactive deployment wizard for claude-toolkit. Walks through
  options and builds the deploy.sh CLI command.
disable-model-invocation: true
---

# Deploy Wizard

Interactive deployment wizard for claude-toolkit. Guides you through selecting scope, items, and options, then builds and runs the `./deploy.sh` command.

## Prerequisites

This skill must be run from the claude-toolkit repo root where `./deploy.sh` exists. If not found, tell the user and stop.

## Steps

### 1. Detect repo root

Verify `./deploy.sh` exists in the current working directory. If not, tell the user:

> This skill must be run from the claude-toolkit repo root (where `deploy.sh` lives).

Then stop.

### 2. Discover available items

Run the discovery script from the repo root:

```bash
~/.claude/skills/deploy/bin/discover .
```

This outputs JSON with `tools`, `hooks`, and `mcp` arrays. Each item has `name`, `enabled`, `scope`, and `on_path` fields.

Parse the output and present a summary table grouped by category (**Skills**, **Hooks**, **MCP**) showing:

| Name | Enabled | Scope | On-path |
|------|---------|-------|---------|

Use defaults (`enabled: true`, `scope: global`, `on_path: false`) when no `deploy.json` exists.

### 3. Ask: Scope

Use `AskUserQuestion` with header "Scope":

- **Global** (Recommended) — deploy skills to `~/.claude/commands/`
- **Project** — deploy skills to a project's `.claude/commands/`. If selected, ask a follow-up question for the project path (suggest the current working directory as default).

### 4. Ask: What to deploy

Use `AskUserQuestion` with header "Items":

- **Everything** (Recommended) — all tools, hooks, and MCP items
- **Select by category** — follow up with a multi-select `AskUserQuestion` listing available categories (Skills, Hooks, MCP). Build `--include` from all items in the selected categories.
- **Select individual items** — follow up with a multi-select `AskUserQuestion` listing every discovered item by name. Build `--include` from selections.
- **Exclude specific items** — follow up with a multi-select `AskUserQuestion` listing every discovered item. Build `--exclude` from selections.

### 5. Ask: On-path

Use `AskUserQuestion` with header "On-path":

- **No** (Recommended) — don't symlink to `~/.local/bin/`
- **Yes** — add `--on-path` to symlink scripts to `~/.local/bin/` for direct CLI use

### 6. Build the command

Construct the full `./deploy.sh` command from the collected answers. Display it to the user:

```
Command to run:
./deploy.sh [flags]
```

### 7. Dry run

Execute the command with `--dry-run` appended and show the output to the user.

### 8. Ask: Proceed

Use `AskUserQuestion` with header "Confirm":

- **Yes, deploy** — run the actual command
- **Adjust options** — go back to step 3 and re-collect options
- **Cancel** — stop without deploying

### 9. Execute

If the user chose "Yes, deploy", run the command (without `--dry-run`), show the output, and confirm success.
