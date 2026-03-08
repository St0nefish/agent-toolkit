---
name: frontmatter-query
description: >-
  Query YAML frontmatter across markdown files. REQUIRED for discovering and
  filtering markdown files by metadata — do NOT use raw grep, awk, or sed to
  parse frontmatter. Use when listing frontmatter fields across files, searching
  for files by metadata key-value pairs, or counting tag/category distributions.
allowed-tools: Bash
---

# Frontmatter Query

Use `${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query` to query YAML frontmatter in markdown files. Do NOT parse frontmatter manually with grep, awk, or sed.

## Subcommands

### List all frontmatter

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query list path/to/dir
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query list path/to/file.md
```

Returns a JSON array of `{path, ...metadata}` for every `.md` file with frontmatter.

### Search by key-value

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query search path/ -k allowed-tools -v Bash
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query search path/ -k tags -v python
```

Filters to files where the key matches the value. Matching is case-insensitive and supports list membership (e.g., a `tags: [python, cli]` field matches `-v python`).

### Count tag values

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query tags path/
${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query tags path/ -k allowed-tools
```

Returns `{"value": count, ...}` sorted by count descending. Defaults to the `tags` key; use `-k` to aggregate a different key.

## Shared flags

| Flag | Effect |
|------|--------|
| `--limit N` | Return at most N results |
| `--body` | Include markdown body in output |
| `--keys k1,k2` | Only include these frontmatter keys (plus `path`) |

## Typical workflow

1. **Discover** — `frontmatter-query list skills/` to see all skill metadata
2. **Filter** — `frontmatter-query search skills/ -k allowed-tools -v Bash` to find skills using Bash
3. **Read** — Use the `Read` tool on specific files from the results

## Exit codes

- 0: Success
- 1: Bad usage / invalid arguments
- 2: Path not found

## Hook auto-approval

Commands using `${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-query` can be auto-approved in Claude Code hooks. This is safe because the script is read-only (stdout output only, no disk writes).
