---
name: markdown-format
description: >-
  Format and auto-fix markdown files using markdownlint-cli2.
  Use when fixing lint violations, cleaning up markdown style, or
  auto-formatting .md files.
allowed-tools: Bash
---

# Format Markdown

Auto-fix markdown lint violations using [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2).

## Usage

Fix a single file:

```bash
markdownlint-cli2 --fix README.md
```

Fix all markdown in a directory:

```bash
markdownlint-cli2 --fix "docs/**/*.md"
```

Fix everything in the repo:

```bash
markdownlint-cli2 --fix "**/*.md"
```

## Notes

- Modifies files in-place — only run on files you intend to change
- Respects `.markdownlint-cli2.yaml` / `.markdownlint.jsonc` config in the project
- Not all rules are auto-fixable — check output for remaining violations
- Exit code 0 = all fixed or clean, non-zero = unfixable violations remain
- Install: `brew install markdownlint-cli2` (macOS) or `npm install -g markdownlint-cli2`
