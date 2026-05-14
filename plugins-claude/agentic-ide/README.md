# Agentic IDE

IDE-grade code intelligence for agents — Serena (LSP symbol navigation and refactoring), ast-grep (AST structural search and rewrite), and Semgrep (security and dataflow analysis) bundled with usage cheatsheets, setup helpers, and a context-isolated explorer agent.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/agentic-ide
```

Then install the required tools:

```bash
/agentic-ide:setup
```

## Tools Bundled

| Tool | What it does |
|------|-------------|
| **Serena** | LSP-backed symbol navigation, cross-file rename, and symbol-level read/write. Understands what a name *means*. |
| **ast-grep** | Structural search and bulk rewrite by AST shape. Understands the *shape* of code. |
| **Semgrep** | Security audits and taint-flow analysis. Understands *types and dataflow*. |

The three tools are orthogonal. The `code-intel` skill (auto-triggered) routes between them by intent and documents tool-specific pitfalls.

## Skills

| Skill | Type | Description |
|-------|------|-------------|
| `code-intel` | Model-triggered | Routing guide — picks the right tool for symbol nav, rename, structural search, security audit, or dataflow; documents Serena pitfalls, ast-grep wildcards, and Semgrep rule patterns |
| `/agentic-ide:setup` | User-invoked | Status check and install instructions for all three tools |

## Agent

`serena-explorer` is a context-isolated subagent (model: Haiku) for heavy Serena meta-analysis. Use it for queries where Serena's verbose JSON output would consume significant context in the parent — call graphs, blast-radius analysis for renames, cross-module dependency mapping, dead-code candidates. The agent absorbs the JSON in its own context and returns a concise synthesis. Read-only — it never modifies the codebase.

The parent agent spawns it automatically via the `serena-explorer` subagent type.

## Setup

Run `/agentic-ide:setup` to check what's installed and get per-tool instructions. Both Serena and Semgrep are MCP servers installed via `uv`; ast-grep is a plain CLI.

### Quick reference

| Tool | Install | MCP registration |
|------|---------|-----------------|
| Serena | `uv tool install --from git+https://github.com/oraios/serena serena` | Required — see `/agentic-ide:setup` |
| ast-grep | `cargo install ast-grep --locked` or `brew install ast-grep` | None (plain CLI) |
| Semgrep | `uv tool install semgrep-mcp` | Required — see `/agentic-ide:setup` |

`uv` itself installs via `curl -LsSf https://astral.sh/uv/install.sh | sh` or `brew install uv`.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `uv` | Yes | Install Serena and Semgrep MCP servers |
| `serena` | Yes | LSP symbol intelligence (`mcp__serena__*` tools) |
| `semgrep-mcp` | Yes | Security and dataflow scanning (`mcp__semgrep__*` tools) |
| `ast-grep` | Yes | Structural search and rewrite CLI |
