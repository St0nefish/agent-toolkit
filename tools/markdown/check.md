---
description: >-
  Lint markdown files for style violations using markdownlint-cli2. REQUIRED
  for markdown linting — do NOT run markdownlint-cli2 directly.
  Use when checking markdown quality, validating style rules, or auditing
  .md files before committing. Read-only — does not modify files.
---

# Check Markdown

Lint markdown files for style violations using [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2).

## Usage

Check a single file:

```bash
markdownlint-cli2 README.md
```

Check all markdown in a directory:

```bash
markdownlint-cli2 "docs/**/*.md"
```

Check everything in the repo:

```bash
markdownlint-cli2 "**/*.md"
```

## Notes

- Read-only, safe for auto-approval
- Respects `.markdownlint-cli2.yaml` / `.markdownlint.jsonc` config in the project
- Exit code 0 = no violations, non-zero = violations found
- Use `/markdown:format` to auto-fix violations
- Install: `brew install markdownlint-cli2` (macOS) or `npm install -g markdownlint-cli2`
