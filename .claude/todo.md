# Project TODO

Project-level roadmap and investigation items. Not for tracking individual session tasks.
Delete completed items — code and git history are the record. Keep this file lean for token efficiency.

## Tools & Skills

- [ ] Investigate `frontmatter-query` tool — wrap `frontmatter` CLI + `jq` to query YAML frontmatter across markdown files. Subcommands: `list`, `search` (by key/value), `tags`. JSON output.
- [ ] Build `/review` skill — structured code review guide (security, correctness, performance, style). Pure skill, no bin/ needed. Consider subagent pattern for parallel review.
- [ ] Investigate `repomix` tool — wrap `repomix` to pack a repo into a single AI-friendly context file. Supports `--compress` for Tree-sitter token reduction (~70%).
- [ ] Investigate `convert-doc` tool — wrap `pandoc` for markdown-to-PDF/DOCX/HTML conversion. Condition check for `pandoc` availability.
- [ ] Add Wayland support to `image` skill — `paste-image` currently uses `xclip` (X11) on Linux; add `wl-paste` fallback for Wayland sessions.

## Deployment

- [ ] Rethink `deploy.json` config files. Currently only consumed by `deploy.sh` — the `/deploy` skill ignores them. Either: (a) have the skill read config files as starting defaults and write back user choices so subsequent runs reuse the same config, or (b) drop config files entirely and let the skill be the sole interface. Evaluate which approach is simpler.

## Hooks

- [ ] Investigate `notify-on-stop` hook — desktop notification when Claude finishes a task. Platform detection (macOS: `osascript`, Linux: `notify-send`). Async, non-blocking.
- [ ] Investigate `auto-checkpoint` hook — git stash or WIP commit on Stop when there are uncommitted changes. Configurable via env var.

## MCP Servers

- [ ] Investigate Context7 (`upstash/context7`) — version-specific library docs at query time. Add config example and document setup.
- [ ] Investigate Memory MCP (`modelcontextprotocol/servers`) — persistent knowledge graph across sessions. Evaluate fit with markdown workflows.
- [ ] Investigate GitHub MCP (`github/github-mcp-server`) — PR/issue management. Evaluate overlap with existing `gh` CLI permissions.
- [ ] Investigate Obsidian MCP / MCP-Markdown-RAG — vault search/read/write or semantic search over markdown. Evaluate which fits (`cyanheads/obsidian-mcp-server` vs `Zackriya-Solutions/MCP-Markdown-RAG`).
