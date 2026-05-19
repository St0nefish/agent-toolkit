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

Inspect the repository for frontmatter constraints without relying on plugin helper-script paths:

- look for nearby markdown files with similar frontmatter
- search for frontmatter schema or taxonomy files
- search for existing validation commands or scripts already tracked in the repo

Build a compact summary of:

- required fields
- constrained values (type, domain, status, tags, etc.)
- the most likely target directory and filename pattern

### 2. Confirm with user

Use `AskUserQuestion` to confirm:

- **Create mode**: proposed filename, location, title, and document type
- **Update mode**: the target file and what changes to make

Show the discovered schema source (if any) so the user can verify it is correct.

### 3. Write the document

- **Create**: Write a new markdown file with YAML frontmatter. Required fields: `title`, `date` (YYYY-MM-DD). Include constrained fields from the discovered schema.
- **Update**: Read the existing file, apply changes, preserve existing frontmatter.

### 4. Validate frontmatter

If the repository already has a frontmatter validation command or script, run it.
Otherwise, manually verify that the frontmatter is valid YAML and that constrained
fields match the discovered schema or local conventions.

Fix any issues and re-check until clean.

### 5. Lint

If `rumdl` is available, run it with auto-fix:

```bash
rumdl check --fix <file>
```

If the file was modified, re-check frontmatter. If `rumdl` is not installed, skip and inform the user.

### 6. Offer to commit

Use `AskUserQuestion` — never auto-commit. If approved, stage and commit with a descriptive message.
