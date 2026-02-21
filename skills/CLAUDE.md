# Skills Directory

This directory contains reusable Claude Code skills. Each skill teaches Claude how and when to use a specific tool or workflow. Skills deploy to `~/.claude/skills/` (or a project's `.claude/skills/`) and become available as slash commands.

See the root `CLAUDE.md` for full deployment, config, and permission documentation.

## How to Add a New Skill

### 1. Create the skill directory

Use a short, lowercase, hyphenated name that matches how users would invoke it (e.g., `jar-explore`, `convert-doc`, `session`).

### 2. Write the script (if needed)

Not every skill needs a script. Skills that wrap existing CLI tools (e.g., `pandoc`, `markdownlint-cli2`) can skip `bin/` entirely and reference those commands directly in the `.md`. If a script is needed, create `skills/<name>/bin/<script>` (executable, no extension for the primary script).

### 3. Write the skill definition

Create `skills/<name>/<name>.md` (or multiple `.md` files for multi-skill tools).

### 4. Add deploy.json (if needed)

Create `skills/<name>/deploy.json` for permissions, scope, or path options.

### 5. Deploy

```bash
./deploy
```

---

## Directory Structure

### Single-skill tool (most common)

```
skills/my-tool/
    bin/
        my-tool          ← executable script (no extension)
    my-tool.md           ← skill definition
    deploy.json          ← optional deployment config
```

### Multi-skill tool (one `bin/`, multiple skills)

```
skills/session/
    bin/
        catchup          ← shared scripts used by multiple skills
        handoff
    start.md             ← skill: /session-start
    end.md               ← skill: /session-end
    checkpoint.md        ← skill: /session-checkpoint
    deploy.json
```

Each `.md` file becomes a separate skill named `<tool>-<stem>` (e.g., `session/start.md` → `/session-start`).

### Script-free tool (wraps an external CLI)

```
skills/convert-doc/
    convert-doc.md       ← skill definition (references pandoc directly)
    deploy.json          ← optional: permission entries for pandoc
```

---

## Script Conventions (`bin/<script>`)

- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail` immediately after shebang
- Errors to stderr (`>&2`), data to stdout
- `usage()` function that prints help and exits 1
- Subcommands dispatched via `case` statement
- Temp files in `/tmp` with `trap cleanup EXIT`
- Exit codes: 0 success, 1 bad usage, 2 file/path not found, 3 entry not found

Template:

```bash
#!/usr/bin/env bash
# tool-name — one-line description
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tool-name <subcommand> [args...]
Subcommands:
  list  <arg>   Description
  read  <arg>   Description
EOF
    exit 1
}

cmd_list() { ... }
cmd_read()  { ... }

[[ $# -lt 1 ]] && usage
subcommand="$1"; shift
case "$subcommand" in
    list)      cmd_list "$@" ;;
    read)      cmd_read "$@" ;;
    -h|--help) usage ;;
    *) echo "Unknown subcommand: $subcommand" >&2; usage ;;
esac
```

---

## Skill Definition Conventions (`<name>.md`)

### Frontmatter

```yaml
---
description: >-
  What the skill does — action verbs matching how users phrase tasks.
  REQUIRED for X operations — do NOT use raw <command> directly.
  Use when <trigger scenario 1>, <trigger scenario 2>.
allowed-tools: Bash, Read
---
```

- **`description`** (required) — Seen by Claude in the system reminder before opening the skill. Formula: (1) what it does, (2) what raw commands it replaces, (3) when to use it.
- **`allowed-tools`** (recommended) — Comma-separated tools the skill may use: `Bash`, `Read`, `Edit`, `Write`, `AskUserQuestion`, `WebFetch`.
- **`disable-model-invocation: true`** (optional) — Hides the skill from Claude's autonomous triggering; only activates via explicit `/command`. Use for user-initiated workflows (session start/end, handoff).

### Body

- H1 title
- Subcommands with copy-paste examples using the full deployed path (`~/.claude/tools/<name>/bin/<script>`)
- Typical workflow (numbered steps)
- Exit codes
- "Hook auto-approval" note if the tool is read-only

For trivial single-action skills, the body can be a single sentence (see `image/paste.md`).

Always reference scripts via deployed path, never relative:

```bash
~/.claude/tools/my-tool/bin/my-tool list /some/path
```

---

## deploy.json Options

```json
{
  "scope": "global",
  "on_path": false,
  "dependencies": ["other-tool"],
  "permissions": {
    "allow": [
      "Bash(~/.claude/tools/my-tool/bin/my-tool)",
      "Bash(~/.claude/tools/my-tool/bin/my-tool *)"
    ]
  }
}
```

- **`scope: "global"`** (default) — deploy to `~/.claude/skills/`
- **`scope: "project"`** — only deploy when `--project` flag is given
- **`on_path: true`** — also symlink scripts to `~/.local/bin/`
- **`dependencies: ["other-tool"]`** — deploy another tool's `bin/` alongside this one
- **`permissions.allow`** — always include both bare and wildcard forms for each command; for external CLIs use `"Bash(pandoc *)"` style

User-local overrides go in `deploy.local.json` (gitignored). See root `CLAUDE.md` for full config precedence.

---

## Common Patterns Across Existing Skills

- **Disambiguation**: When a skill overlaps with another tool, the description explicitly states what each handles.
- **Read-only auto-approval note**: Scripts that never write to disk include a "Hook auto-approval" section and bare+glob permission entries in `deploy.json`.
- **Single-line body**: Skills with one action use a single-sentence body (see `image/paste.md`).
- **`disable-model-invocation`**: User-initiated workflows (session lifecycle, handoff) always set this to `true`.
- **Full deployed path in examples**: All bash examples use `~/.claude/tools/<name>/bin/<script>`.
- **Shared `bin/` with multiple `.md` files**: Skills sharing scripts live in one directory with one `deploy.json`.