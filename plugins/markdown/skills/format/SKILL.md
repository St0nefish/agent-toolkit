---
name: markdown-format
description: >-
  Format and auto-fix markdown files using rumdl.
  Use when fixing lint violations, cleaning up markdown style, or
  auto-formatting .md files.
allowed-tools: Bash
---

# Format Markdown

Auto-fix markdown lint violations using [rumdl](https://github.com/sysid/rumdl).

## Usage

Fix a single file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix README.md
```

Fix all markdown in a directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix docs/
```

Fix everything in the repo:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix .
```

## Notes

- Modifies files in-place — only run on files you intend to change
- Respects `.rumdl.toml` config in the project
- Not all rules are auto-fixable — check output for remaining violations
- Exit code 0 = all fixed or clean, non-zero = unfixable violations remain
- If rumdl is not found, run `/markdown:setup`
