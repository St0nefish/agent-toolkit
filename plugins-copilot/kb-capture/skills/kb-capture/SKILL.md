---
user-invocable: false
name: kb-capture
description: >-
  Capture conversation findings as a markdown document with schema-valid
  frontmatter. Triggers when the user says "document this", "write this up",
  "capture this", "update the doc", "save this to the KB", or similar requests
  to persist research or discussion findings as a markdown file. Handles both
  creating new documents and updating existing ones.
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# KB Capture

Automate the research-to-document workflow: discover local frontmatter conventions,
write schema-valid markdown with frontmatter, lint, and optionally commit.

## Mode Detection

- **Create** — user wants a new document (default when no existing file is referenced)
- **Update** — user references an existing file to modify

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

Show the discovered schema source (if any) so the user can verify it is the right one.

### 3. Write the document

- **Create**: Write a new markdown file with YAML frontmatter containing all required fields (`title`, `date` in YYYY-MM-DD format) and any constrained fields from the discovered schema. Use the conversation context to populate the document body.
- **Update**: Read the existing file, apply the requested changes, and preserve existing frontmatter fields.

### 4. Validate frontmatter

If the repository already has a frontmatter validation command or script, run it.
Otherwise, manually verify that the frontmatter is valid YAML and that constrained
fields match the discovered schema or local conventions.

If validation fails, fix the reported issues and re-check.

### 5. Lint

If `rumdl` is available, run it with auto-fix:

```bash
rumdl check --fix <file>
```

If the file was modified by the linter, re-check frontmatter to ensure fixes did not break it. If `rumdl` is not installed, skip linting and inform the user.

### 6. Offer to commit

Use `AskUserQuestion` to ask whether to commit and push the changes. **Never auto-commit.** If the user agrees, stage the file and commit with a descriptive message.

## Rules

- Always derive constrained frontmatter values from the repository's actual schema files, validators, or nearby examples — do not guess.
- Date fields must use YYYY-MM-DD format.
- Tags should be YAML flow sequences: `tags: [tag1, tag2]`.
- Run validation and linting on every write, even updates.
