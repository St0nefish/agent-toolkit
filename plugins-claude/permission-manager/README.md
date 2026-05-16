# Permission Manager

Bash command safety classifier with shfmt-based AST parsing, extensible custom patterns, WebFetch domain management, and audit logging.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/permission-manager
```

Then install required dependencies:

```bash
/permission-manager:setup
```

## How It Works

Every Bash command Claude runs passes through a classification pipeline that parses it into an AST using `shfmt --tojson`, segments compound commands (pipes, `&&`, `||`, `;`), and classifies each segment independently through an ordered chain of classifiers.

### Three Decision Buckets

| Decision | Meaning |
|----------|---------|
| **allow** | Read-only or safe local operation — auto-approved |
| **ask** | Write/modifying command — prompts the user for confirmation |
| **deny** | Destructive operation — hard-blocked |

For compound commands, the **most restrictive** decision wins: deny > ask > allow.

### Classification Pipeline

1. **Dependency check** — if `shfmt` or `jq` are missing, all Bash commands are denied with an install message (the `/permission-manager:setup` command itself is allowed through via a bootstrap bypass so you can recover)
2. **Redirection check** — denies `>` and `>>` redirections (except stderr, `/dev/null`, and `/tmp/`)
3. **Inline Python check** — for `python[3] -c "..."` or `python[3] -m <module>` invocations, statically analyses the inline source via `check-python-readonly.py` (allowlisted imports, read-only `open()`, no subprocess/exec/network/dunder escapes); allow when safe, ask with reason when unsafe
4. **shfmt AST parsing** — segments compound commands into individual call expressions
5. **Per-segment classification** — each segment runs through the classifier chain (first match wins):
   1. Custom user patterns
   2. Allow-edit commands (when in accept-edits mode)
   3. `find` safety
   4. Read-only tools (shell builtins, text tools, system inspection)
   5. `git` subcommands
   6. `gradle`/`gradlew`
   7. `gh` (GitHub CLI)
   8. `tea` (Gitea CLI)
   9. `docker` (including recursive classification of `docker exec` inner commands)
   10. `npm`/`node`/`yarn`/`pnpm`/`nvm`/`deno`/`npx`
   11. `pip`/`python`/`poetry`/`pyenv`/`uv`
   12. `cargo`/`rustc`/`rustup`
   13. JVM tools (`java`/`javac`/`javap`/`mvn`/`jar`/`kotlin`)
6. **Aggregate** — most restrictive across all segments wins
7. **Audit log** — all decisions are appended to `~/.claude/permission-audit.jsonl`

### What Gets Classified

The classifiers understand subcommand semantics. For example, `git log` is allowed but `git reset --hard` is denied. `docker exec` extracts the inner command and recursively classifies it. `npm install` is allowed (local build) but `npm publish` prompts.

Protected branches (`main`, `master`) get special treatment — `git push` to them is denied, `git branch -D` targeting them is denied.

## Commands

Dependency setup is its own top-level command:

| Command | Description |
|---------|-------------|
| `/permission-manager:setup` | Install `shfmt` and `jq` (allowed through the hook via a bootstrap bypass) |

All other management is through `/permission-manager:config [action]`:

| Action | Description |
|--------|-------------|
| `commands` | Manage custom command patterns — `list`, `add --scope global\|project`, `remove` |
| `allow-edit` | Manage the allow-edit command list for accept-edits mode |
| `web` | Manage WebFetch/WebSearch domain permissions |
| `explain` | Trace the classification pipeline for any command |
| `learn` | Analyze the audit log and suggest custom patterns for frequently seen commands |

## Custom Patterns

Add glob patterns to auto-allow commands you run frequently:

```bash
/permission-manager:config commands add --scope project
# Then provide patterns like: docker exec myapp cat *
```

Patterns are stored in `command-permissions.json` at two scopes:

- **Global:** `~/.claude/command-permissions.json`
- **Project:** `.claude/command-permissions.json`

Both are merged. Patterns use bash glob matching against the full command string.

### Learning From History

The `/permission-manager:config learn` action analyzes your audit log to find commands that are frequently prompted and suggests glob patterns:

```bash
/permission-manager:config learn
# Scans ~/.claude/permission-audit.jsonl
# Groups by command prefix, computes glob patterns
# Offers to add them to your config
```

## Allow-Edit Mode

When Claude Code is in `acceptEdits` permission mode, the allow-edit classifier activates. It auto-approves a set of file-manipulation commands (`chmod`, `ln`, `mkdir`, `cp`, `mv`, `touch`, `install`, `tee`) — but only when all target paths resolve within the project directory.

Customize the command list:

```bash
/permission-manager:config allow-edit
```

Config files: `~/.claude/allow-edit-permissions.json` (global), `.claude/allow-edit-permissions.json` (project).

## WebFetch/WebSearch Gating

Separately from Bash commands, the plugin gates web access with three modes:

| Mode | Behavior |
|------|----------|
| `off` | Passthrough — Claude Code's built-in permissions apply |
| `all` | Allow all GET/HEAD requests; mutating methods (POST/PUT/DELETE) prompt |
| `domains` | Per-domain allow-list with subdomain matching (e.g. `github.com` matches `api.github.com`) |

```bash
/permission-manager:config web
```

Config files: `~/.claude/web-permissions.json` (global), `.claude/web-permissions.json` (project). Project mode overrides global; domain lists are merged.

## Debugging

Trace exactly how any command would be classified:

```bash
/permission-manager:config explain 'git push origin feature/42-export && docker exec app cat /etc/nginx.conf'
```

This runs the full pipeline with instrumented output showing each classifier's decision per segment.

## Audit Log

All decisions are logged to `~/.claude/permission-audit.jsonl` in JSONL format:

```json
{"ts":"...","command":"...","decision":"allow","reason":"git: log (read-only)","mode":"default","project":"my-app","cwd":"..."}
```

Override the log location with the `PERMISSION_AUDIT_LOG` environment variable.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `shfmt` | Yes | Shell AST parsing via `--tojson` |
| `jq` | Yes | JSON processing for AST traversal and config |
| `perl` | Yes | Regex checks in classifiers (standard on macOS/Linux) |
| `python3` | Optional | Static read-only check for `python -c` payloads (falls through to ask if missing) |

Install via `/permission-manager:setup` (supports Homebrew, apt, dnf, pacman, and `go install` for shfmt).

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PERMISSION_AUDIT_LOG` | `~/.claude/permission-audit.jsonl` | Audit log location |
| `COMMAND_PERMISSIONS_GLOBAL` | `~/.claude/command-permissions.json` | Global custom patterns |
| `COMMAND_PERMISSIONS_PROJECT` | `.claude/command-permissions.json` | Project custom patterns |
| `ALLOW_EDIT_PERMISSIONS_GLOBAL` | `~/.claude/allow-edit-permissions.json` | Global allow-edit commands |
| `ALLOW_EDIT_PERMISSIONS_PROJECT` | `.claude/allow-edit-permissions.json` | Project allow-edit commands |
| `WEB_PERMISSIONS_GLOBAL` | `~/.claude/web-permissions.json` | Global web config |
| `WEB_PERMISSIONS_PROJECT` | `.claude/web-permissions.json` | Project web config |
