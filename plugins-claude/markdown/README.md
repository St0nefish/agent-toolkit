# Markdown

Markdown linting and formatting using `rumdl`.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/markdown
```

## Commands

| Command | Description |
|---------|-------------|
| `/markdown:markdown check` | Run the linter (read-only) |
| `/markdown:markdown format` | Auto-fix lint violations in-place |
| `/markdown:markdown setup` | Instructions to install `rumdl` |

Respects `.rumdl.toml` configuration in your project.

## Dependencies

| Tool | Required | Install |
|------|----------|---------|
| `rumdl` | Yes | `cargo install rumdl` or `brew install rumdl` |
