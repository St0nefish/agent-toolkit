---
name: markdown-check
description: >-
  Lint markdown files for style violations using rumdl.
  Use when checking markdown quality, validating style rules, or auditing
  .md files before committing. Read-only — does not modify files.
allowed-tools: Bash
---

# Check Markdown

Lint markdown files for style violations using [rumdl](https://github.com/sysid/rumdl).

## Usage

Check a single file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check README.md
```

Check all markdown in a directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check docs/
```

Check everything in the repo:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check .
```

## Notes

- Read-only, safe for auto-approval
- Respects `.rumdl.toml` config in the project
- Exit code 0 = no violations, non-zero = violations found
- Use `/markdown:format` to auto-fix violations
- If rumdl is not found, run `/markdown:setup`
