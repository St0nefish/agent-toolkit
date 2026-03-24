---
description: "Capture findings as schema-valid markdown with frontmatter, linting, and optional commit"
argument-hint: "[create|update] [filename]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# KB Capture

Capture conversation findings or research as a markdown document with schema-valid frontmatter.

## Argument Dispatch

- `/kb-capture:capture create` — force create mode (new document)
- `/kb-capture:capture update <file>` — force update mode on the given file
- `/kb-capture:capture` (no args) — detect mode from conversation context

## Steps

### 1. Detect schema

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-schema.sh
```

Returns JSON with valid frontmatter field values. Empty fields if no schema found.

### 2. Confirm with user

Use `AskUserQuestion` to confirm:

- **Create mode**: proposed filename, location, title, and document type
- **Update mode**: the target file and what changes to make

Show the detected schema file (if any) so the user can verify it is correct.

### 3. Write the document

- **Create**: Write a new markdown file with YAML frontmatter. Required fields: `title`, `date` (YYYY-MM-DD). Include constrained fields from schema output.
- **Update**: Read the existing file, apply changes, preserve existing frontmatter.

### 4. Validate frontmatter

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-frontmatter.sh <file>
```

Fix any issues (exit 1) and re-validate until clean (exit 0).

### 5. Lint

If `rumdl` is available, run it with auto-fix:

```bash
rumdl check --fix <file>
```

If the file was modified, re-validate frontmatter. If `rumdl` is not installed, skip and inform the user.

### 6. Offer to commit

Use `AskUserQuestion` — never auto-commit. If approved, stage and commit with a descriptive message.
