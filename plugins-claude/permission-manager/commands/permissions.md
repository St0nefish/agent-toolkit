---
description: "Permission management — commands, allow-edit, setup, web, explain, learn"
argument-hint: "[action]"
allowed-tools: Bash, Read, AskUserQuestion
disable-model-invocation: true
---

# Permissions

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `commands`, `allow-edit`, `setup`, `web`, `explain`, `learn`. Usage: `/permissions [action]`)

---

## commands

Manage custom command patterns for the cmd-gate hook.

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

## allow-edit

Manage the allow-edit command list for allow-edits permission mode.

In allow-edits mode, commands in this list are auto-approved when all path arguments are within the project directory. Built-in defaults: `chmod`, `ln`, `mkdir`, `cp`, `mv`, `touch`, `install`, `tee`.

### Config files

| Scope | File | Use case |
|-------|------|----------|
| Global | `~/.claude/allow-edit-permissions.json` | Personal safe-write preferences |
| Project | `.claude/allow-edit-permissions.json` | Project-specific safe writes |

### Instructions

Follow these steps exactly:

#### 1. Show current allow-edit commands

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh list --type allow-edit
```

Display the output to the user.

#### 2. Ask what the user wants to do

Use `AskUserQuestion` to ask:

- **Add a command** — prompt for the command name and scope (global or project)
- **Remove a command** — prompt for which command to remove and its scope
- **Done** — exit

#### 3. Execute the action

To add:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh add --type allow-edit --scope <scope> '<command>'
```

To remove:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh remove --type allow-edit --scope <scope> '<command>'
```

#### 4. Show updated state and repeat

After each action, re-run `list --type allow-edit` to show the updated commands, then go back to step 2.

---

## setup

Install the required dependencies for the cmd-gate hook.

### Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-deps.sh
```

Report the result to the user. If installation fails, show the manual install links from the script output.

---

## web

Manage web permissions (WebFetch + WebSearch) in `~/.claude/settings.json`.

Two modes are available:

- **all** — blanket allow for WebFetch and WebSearch (no domain restrictions)
- **domains** — curated domain allow-list plus WebSearch, with custom domain management

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

#### 2. Check for --mode argument

If the user passed `--mode all` or `--mode domains` (e.g. `/permissions web --mode all`), skip step 3 and jump directly to the appropriate apply step (4a or 4b).

#### 3. Ask user to select a mode

Use `AskUserQuestion` to ask:

> How should web permissions be configured?
>
> - **Allow all domains** — blanket WebFetch + WebSearch (no restrictions)
> - **Domain-scoped** — curated domain list + WebSearch + custom domain management
> - **Manage custom domains** — add or remove individual domain entries (only available when domain-scoped mode is active)

If "Manage custom domains" is selected but `web-all` is currently applied (not `web`), inform the user they need to switch to domain-scoped mode first, then re-ask.

#### 4a. Apply `all` mode

Dry-run first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --dry-run web-all
```

Show the output. Ask the user to confirm. If approved:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh web-all
```

Report the result.

#### 4b. Apply `domains` mode

First, remove any blanket web-all entries (safe no-op if not applied):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --remove web-all
```

Then dry-run the domain group:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh --dry-run web
```

Show the output. Ask the user to confirm. If approved:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/merge-permissions.sh web
```

Report the result.

#### 4c. Manage custom domains

Show the current WebFetch domain entries from settings.json:

```bash
jq -r '.permissions.allow // [] | .[] | select(startswith("WebFetch(domain:"))' ~/.claude/settings.json
```

Use `AskUserQuestion` to ask:

> What would you like to do?
>
> - **Add a domain** — add a new WebFetch domain entry
> - **Remove a domain** — remove an existing WebFetch domain entry
> - **Done** — exit

**Add:** Ask for the domain name, then add it:

```bash
jq --arg entry "WebFetch(domain:<domain>)" '.permissions.allow = ((.permissions.allow // []) + [$entry] | unique | sort)' ~/.claude/settings.json > /tmp/settings-tmp.json && mv /tmp/settings-tmp.json ~/.claude/settings.json
```

**Remove:** Ask which domain to remove, then delete it:

```bash
jq --arg entry "WebFetch(domain:<domain>)" '.permissions.allow = [(.permissions.allow // [])[] | select(. != $entry)]' ~/.claude/settings.json > /tmp/settings-tmp.json && mv /tmp/settings-tmp.json ~/.claude/settings.json
```

After each action, show the updated domain list and loop back to the question.

---

## explain

Trace the classification pipeline for a specific command.

### Instructions

Follow these steps exactly:

#### 1. Ask for the command

Use `AskUserQuestion` to ask:

> What Bash command would you like to trace through the classifier?

#### 2. Run the explain script

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/explain.sh '<command>'
```

#### 3. Display the output

Show the full trace output to the user. If the output shows `NONE` (no classifier matched), explain that the command would fall through to Claude Code's built-in permission system.

---

## learn

Review permission decisions and adjust allow-list patterns.

### Instructions

Follow these steps exactly:

#### 1. Ask what to review

Use `AskUserQuestion` to ask:

> What would you like to review?
>
> - **Commands that were blocked** — find commands you keep approving so you can allow them (default)
> - **Commands that were allowed** — find commands that slipped through that should require approval
> - **Both** — review all classified commands

Map the answer to a `--decision` flag: `ask` (blocked), `allow` (allowed), or `all` (both).

#### 2. Check for audit log

```bash
test -f "${PERMISSION_AUDIT_LOG:-$HOME/.claude/permission-audit.jsonl}" && wc -l < "${PERMISSION_AUDIT_LOG:-$HOME/.claude/permission-audit.jsonl}" || echo "0"
```

If the audit log is empty or missing, tell the user and offer manual mode (step 5).

#### 3. Scan the audit log

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/learn.sh scan --decision <decision>
```

If no commands are found, inform the user and offer manual mode (step 5).

Display the commands to the user in a numbered list.

#### 4. Let the user pick commands

Use `AskUserQuestion` with `multiSelect: true` listing the scanned commands. Let the user check the ones they want to address.

#### 5. Choose mode: exact or pattern

Use `AskUserQuestion` to ask:

> How would you like to create rules for these commands?
>
> - **Exact with wildcards** — review each command and replace variable parts (file paths, branch names, container names) with `*` wildcards
> - **Auto-suggest patterns** — analyze structural similarities and suggest glob patterns automatically
> - **Paste commands** — manually enter commands to create rules for (useful when audit log is empty)

#### 6a. Exact with wildcards mode

For each selected command, present it to the user and ask which parts should be replaced with `*`. For example:

> Command: `docker exec app1 cat /etc/nginx/nginx.conf`
>
> Which parts are variable? (replace with `*`)
>
> - `app1` (container name)
> - `/etc/nginx/nginx.conf` (file path)
>
> Suggested pattern: `docker exec * cat *`

Use `AskUserQuestion` to confirm or let them edit the pattern directly.

For `--decision allow` commands (things allowed that shouldn't be), explain that these cannot be added to the allow-list — the user should either file a classifier bug or adjust their workflow. Show the explain trace so they understand why it was allowed:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/explain.sh '<command>'
```

#### 6b. Auto-suggest patterns mode

Pipe the selected commands to the suggest engine:

```bash
echo '<selected-commands>' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/learn.sh suggest
```

Display suggested patterns in a table:

| Pattern | Skeleton | Broad? | Based on |
|---------|----------|--------|----------|
| `docker *exec *cat *` | docker, exec, cat | No | 3 commands |
| `gradle *--dry-run` | gradle, --dry-run | No | 2 commands |

The `skeleton` field shows the fixed tokens the pattern matches on. Flag `broad: true` patterns with a warning.

#### 6c. Paste commands mode

Use `AskUserQuestion` to ask:

> Paste the commands you'd like to create rules for (one per line):

Then pipe the response to suggest:

```bash
echo '<pasted-commands>' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/learn.sh suggest
```

Display the results as in step 6b.

#### 7. Confirm scope and apply

Use `AskUserQuestion` with `multiSelect: true` to let the user choose which patterns to add and their scope (global or project).

For each confirmed pattern, apply it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh add --scope <scope> '<pattern>'
```

#### 8. Show updated state

Run the list command to show the final state:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/manage-custom-patterns.sh list
```
