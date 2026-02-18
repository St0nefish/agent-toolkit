# Toolkit Additions TODO

Additions identified for development and markdown-based knowledge management workflows.
Remove items when they land in the repo — code and git are the record.

## Tools & Skills

### 1. `frontmatter-query` tool

- **Priority:** High — unlocks structured queries across markdown knowledge bases
- **What:** Wraps `frontmatter` CLI + `jq` to query YAML frontmatter across a directory of markdown files
- **Pattern:** `tools/frontmatter-query/` with `bin/frontmatter-query` and `frontmatter-query.md`
- **Notes:** Subcommands: `list` (all files with frontmatter), `search` (by key/value), `tags` (aggregate all tags); JSON output for composability

### 4. `/review` skill

- **Priority:** High — improves code quality with zero dependencies
- **What:** Structured code review guide — walks Claude through security, correctness, performance, style checks
- **Pattern:** `tools/review/review.md` (no `bin/` needed)
- **Notes:** Could use subagent pattern for parallel review perspectives

### 5. `repomix` tool

- **Priority:** Medium — useful for cross-session context sharing
- **What:** Wraps `repomix` to pack a repo/directory into a single AI-friendly context file
- **Pattern:** `tools/repomix/` with `bin/repomix-pack` and `repomix.md`
- **Notes:** Read-only; supports `--compress` for Tree-sitter token reduction (~70%); output to stdout or temp file

### 6. `convert-doc` tool

- **Priority:** Medium — useful for markdown export workflows
- **What:** Wraps `pandoc` for markdown-to-PDF/DOCX/HTML conversion
- **Pattern:** `tools/convert-doc/` with `bin/convert-doc` and `convert-doc.md`
- **Notes:** Subcommands or flag-based format selection; condition check for `pandoc` availability

### 7. `paste-image-linux` tool

- **Priority:** Low — completes the platform matrix
- **What:** `xclip`/`wl-paste` variant for native Linux desktops (X11/Wayland)
- **Pattern:** `tools/paste-image-linux/` with same `paste-image.md` filename for collision-free deployment
- **Notes:** Condition: Linux but NOT WSL; detect X11 vs Wayland for tool selection

## Hooks

### 8. `notify-on-stop` hook (Stop)

- **Priority:** Medium — daily quality-of-life
- **What:** Sends a desktop notification when Claude finishes a task
- **Pattern:** `hooks/notify-on-stop/` with platform detection (macOS: `osascript`, Linux: `notify-send`)
- **Notes:** Async, no blocking; include brief summary of what was done if available from stdin

### 9. `auto-checkpoint` hook (Stop)

- **Priority:** Medium — safety net against lost work
- **What:** Creates a lightweight git stash or WIP commit when Claude stops
- **Pattern:** `hooks/auto-checkpoint/` with `deploy.json` for Stop event
- **Notes:** Only act if there are uncommitted changes; use `git stash push -m "claude-checkpoint <timestamp>"` or a WIP commit on current branch; configurable via env var

## Repo Restructure

### ~~Commands-to-skills migration~~ — Resolved

Staying with `~/.claude/commands/` as the deployment target. Only `commands/` supports colon-namespaced commands (e.g., `/session:start`) via subdirectory symlinks — `skills/` does not. Instead, modernized all skill files with `allowed-tools` and `disable-model-invocation` frontmatter fields.

### Repo restructure (tools/ -> skills/, add mcp/)

- **Priority:** Medium — better naming and separation of concerns
- **What:** Rename `tools/` to `skills/`, create `mcp/` folder, move `jar-explore` to `mcp/`, update `deploy.sh` to iterate `skills/*/` and `mcp/*/` alongside `hooks/*/`. The deploy wizard should support all three categories: Skills, Hooks, MCP.
- **Note:** Deployment target remains `~/.claude/commands/` regardless of source directory naming.

## MCP Servers (document/configure, not deployed by deploy.sh)

### 10. Context7

- **Priority:** High — eliminates stale library doc hallucinations
- **What:** Fetches version-specific library documentation at query time
- **Repo:** `upstash/context7` (46k stars)
- **Action:** Add config example to `mcp-servers/` and document setup

### 11. Memory (official)

- **Priority:** Medium — persistent knowledge graph across sessions
- **What:** Stores entities, relationships, observations; persists across conversations
- **Repo:** `modelcontextprotocol/servers` (official)
- **Action:** Add config example and document integration with markdown workflows

### 12. GitHub MCP

- **Priority:** Medium — PR/issue management
- **What:** Repository browsing, code search, issue/PR management
- **Repo:** `github/github-mcp-server` (27k stars)
- **Action:** Add config example; evaluate overlap with existing `gh` CLI permissions

### 13. Obsidian MCP / MCP-Markdown-RAG

- **Priority:** Medium — if using Obsidian or large markdown corpus
- **What:** Vault search/read/write (Obsidian) or semantic search over markdown files (RAG)
- **Repos:** `cyanheads/obsidian-mcp-server`, `Zackriya-Solutions/MCP-Markdown-RAG`
- **Action:** Evaluate which fits; add config example
