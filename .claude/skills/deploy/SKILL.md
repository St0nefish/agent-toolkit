---
description: >-
  Interactive deployment wizard for claude-toolkit. Walks through
  options and builds the deploy.sh CLI command.
disable-model-invocation: true
---

# Deploy Wizard

Interactive deployment wizard for claude-toolkit.

## Steps

### 1. Discover

Run the discovery script from the current working directory. Use exactly this relative path:

```bash
.claude/skills/deploy/bin/discover .
```

This validates `deploy.sh` exists, detects profiles, and outputs the full merged config for every item. If it fails, show the error and stop.

The output JSON contains: `repo_root`, `profiles` (list of profile filenames), `skills`, `hooks`, `mcp` (arrays of items with `name`, `enabled`, `scope`, `on_path`).

Hold onto this data for all subsequent steps.

### 2. Choose profile

Look at `profiles` from the discover output.

**If profiles exist**, use `AskUserQuestion` with header "Profile":

- One option per profile file (show `global.json` as "Global", others by filename)
- **Create new profile**

If the user picks an existing profile, ask a follow-up: **Deploy as-is** or **Edit first**. If as-is, skip to step 6. If edit, re-run discover with `--profile` and continue to step 4.

**If no profiles exist**, go straight to step 3.

### 3. New profile: scope

Use `AskUserQuestion` with header "Scope":

- **Global** — deploy to `~/.claude/commands/`
- **Project** — deploy to a specific project. Ask follow-up for the project path.

### 4. Items: defaults or select?

Filter the discovered items to those that would actually deploy for the chosen scope. For global: items where `enabled: true` and `scope: "global"`. For project: items where `enabled: true` (any scope). Show the user a simple list of what would be deployed by default — just the names, grouped by category (Skills, Hooks, MCP). No config columns.

Use `AskUserQuestion` with header "Items":

- **Use defaults** — deploy the listed items. Continue to step 6.
- **Select items** — continue to step 5.

### 5. Select items

**Do NOT use `AskUserQuestion` here** — it only supports 4 options which is not enough.

Print a numbered list of **every** discovered item from **all** categories (skills, hooks, mcp), grouped by category. Example:

```
Skills:
  1. catchup
  2. jar-explore
  3. image
  ...
Hooks:
  7. bash-safety
  8. format-on-save
```

Then tell the user to type the numbers they want in their next message (e.g., "1, 2, 5, 7, 8"). Selected = deployed. Everything else = excluded.

**Do NOT use `AskUserQuestion` for this.** Just print the list and wait for the user's reply as a normal message.

### 6. On-path selection

Use `AskUserQuestion` with header "On-path":

- **None** (Recommended) — no scripts on PATH
- **All selected items** — set `on_path: true` for everything selected in step 5
- **Select items** — continue to sub-step below

If "Select items": print only the items the user enabled in step 5, keeping their original index numbers (the list will have gaps where excluded items were). Ask the user to type the numbers they want on PATH. Same plain-text input pattern as step 5.

### 7. Save profile

Write the profile to `.deploy-profiles/`:

- Global → `.deploy-profiles/global.json`
- Project → `.deploy-profiles/<slug>.json` (slug: strip leading `/`, replace `/` with `-`, lowercase)

Profile format — write **every** item grouped by type, not just deltas:

```json
{
  "skills": {
    "catchup": { "enabled": true, "on_path": false },
    "jar-explore": { "enabled": false, "on_path": true }
  },
  "hooks": {
    "bash-safety": { "enabled": true, "on_path": false }
  },
  "mcp": {}
}
```

- Global profiles omit `project_path`. Project profiles include `project_path`.
- The profile's scope is determined by whether `project_path` is present — do NOT put `scope` on individual items. A global profile deploys globally. A project profile deploys to that project.
- Write ALL items under their type — selected get `"enabled": true`, unselected get `"enabled": false`
- The profile is **authoritative**: items not listed are disabled and flagged as new by `deploy.sh`
- Create `.deploy-profiles/` directory if needed

### 8. Dry run

Build and run:

```bash
./deploy.sh --profile .deploy-profiles/<name>.json --dry-run
```

Add `--project <path>` if project-scoped. Show the output.

### 9. Confirm and execute

Use `AskUserQuestion` with header "Confirm":

- **Yes, deploy** — run without `--dry-run`, show output
- **Cancel** — stop
