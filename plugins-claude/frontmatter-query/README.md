# Frontmatter Query

Query YAML frontmatter across markdown files. Model-triggered — fires automatically when Claude needs to search or list metadata in markdown collections.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/frontmatter-query
```

## Operations

| Subcommand | Description |
|------------|-------------|
| `list <path>` | JSON array of all markdown files with their frontmatter |
| `search <path> -k <key> -v <value>` | Filter by key-value (case-insensitive, supports list membership) |
| `tags <path> [-k <key>]` | Count value occurrences for a key (default: `tags`), sorted by frequency |

Shared flags: `--limit N`, `--body` (include markdown body), `--keys k1,k2` (restrict output fields).

## Dependencies

| Tool | Required | Install |
|------|----------|---------|
| `uv` | Yes | `brew install uv` or `pip install uv` |

Uses `uv run` with PEP 723 inline dependencies — no separate `pip install` needed. Requires Python >= 3.12.
