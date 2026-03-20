# KB Capture

Capture conversation findings as schema-valid markdown documents with YAML frontmatter, linting, and optional commit.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/kb-capture
```

## How It Works

When you ask Claude to "document this", "write this up", or "save this to the KB", the plugin:

1. Discovers your project's KB schema (valid field values for `type`, `domain`, `tags`, etc.)
2. Confirms filename, location, and doc type with you
3. Writes the file with valid YAML frontmatter
4. Validates frontmatter against the schema and fixes any issues
5. Lints with `rumdl` if available
6. Offers to commit (never auto-commits)

Also available as an explicit command: `/kb-capture:capture [create|update] [filename]`

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `bash` | Yes | Script execution |
| `rumdl` | No | Markdown linting (skipped if absent) |

The plugin uses `detect-schema.sh` and `validate-frontmatter.sh` from the shared utils — these are bundled via symlinks and require no separate installation.
