# Agentic IDE

IDE-grade code intelligence for agents — Serena (LSP symbol navigation and refactoring) and ast-grep (AST structural search and rewrite) bundled with usage cheatsheets, setup helpers, and a context-isolated explorer agent.

## Installation

```bash
copilot plugin install St0nefish/agent-toolkit:plugins-copilot/agentic-ide
```

For Claude Code:

```bash
claude plugin install St0nefish/agent-toolkit/agentic-ide
```

In Copilot CLI, Serena is registered by the plugin. Its first use in a Git worktree installs
Serena through `uv` when necessary and starts one shared, localhost-only Serena backend for that
absolute worktree path. Additional Copilot sessions connect through lightweight bridges, so they
do not duplicate the backend or its language servers. Claude Code continues to use its setup
skill and a directly registered MCP server.

## Tools Bundled

| Tool | What it does |
|------|-------------|
| **Serena** | LSP-backed symbol navigation, cross-file rename, and symbol-level read/write. Understands what a name *means*. |
| **ast-grep** | Structural search and bulk rewrite by AST shape. Understands the *shape* of code. |

The two tools are orthogonal. The `code-intel` skill (auto-triggered) routes between them by intent and documents tool-specific pitfalls.

## Skills

| Skill | Type | Description |
|-------|------|-------------|
| `code-intel` | Model-triggered | Routing guide — picks the right tool for symbol nav, rename, or structural search; documents Serena pitfalls and ast-grep wildcards |
| `/agentic-ide:setup` | User-invoked | Status check and install instructions for both tools |

## Agent

`serena-explorer` is a context-isolated subagent (model: Haiku) for heavy Serena meta-analysis. Use it for queries where Serena's verbose JSON output would consume significant context in the parent — call graphs, blast-radius analysis for renames, cross-module dependency mapping, dead-code candidates. The agent absorbs the JSON in its own context and returns a concise synthesis. Read-only — it never modifies the codebase.

The parent agent spawns it automatically via the `serena-explorer` subagent type.

## Setup

Run `/agentic-ide:setup` to check prerequisites and get recovery instructions. In Copilot CLI,
Serena is an automatic, plugin-provided MCP server; in Claude Code it is installed and registered
through the setup skill. ast-grep is a plain CLI.

### Quick reference

| Tool | Install | MCP registration |
|------|---------|-----------------|
| Serena | Copilot: automatic through `uv`; Claude: setup skill | Copilot: shared backend; Claude: required |
| ast-grep | `cargo install ast-grep --locked` or `brew install ast-grep` | None (plain CLI) |

`uv` itself installs via `curl -LsSf https://astral.sh/uv/install.sh | sh` or `brew install uv`.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `uv` | Yes | Bootstrap Copilot Serena |
| `systemd --user` | Copilot Serena | Keep one shared Serena backend per worktree |
| `serena` | Copilot: automatic; Claude: setup skill | LSP symbol intelligence (`mcp__serena__*` tools) |
| `ast-grep` | Yes | Structural search and rewrite CLI |
