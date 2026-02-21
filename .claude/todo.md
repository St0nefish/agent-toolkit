# Project TODO

Project-level roadmap and investigation items. Not for tracking individual session tasks.
Delete completed items — code and git history are the record. Keep this file lean for token efficiency.

## Tools & Skills

- [ ] Build `/review` skill — structured code review guide (security, correctness, performance, style). Pure skill, no bin/ needed. Consider subagent pattern for parallel review.

- [ ] Build `/todo` skill — manage project TODO items from Claude Code

## Deploy

## Hooks

- [ ] Enhance stop hook to optionally alert only if awaiting input

## TUI

- [ ] Case-insensitive tab path completion in project selector

## MCP Servers

- [ ] Investigate Memory MCP (`modelcontextprotocol/servers`) — persistent knowledge graph across sessions. Evaluate fit with markdown workflows.
- [ ] Investigate GitHub MCP (`github/github-mcp-server`) — PR/issue management. Evaluate overlap with existing `gh` CLI permissions.
- [ ] Investigate Obsidian MCP / MCP-Markdown-RAG — vault search/read/write or semantic search over markdown. Evaluate which fits (`cyanheads/obsidian-mcp-server` vs `Zackriya-Solutions/MCP-Markdown-RAG`).
