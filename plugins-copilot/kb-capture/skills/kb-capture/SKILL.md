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

Automate the research-to-document workflow: detect the knowledge base schema, write schema-valid markdown with frontmatter, lint, and optionally commit.

## Mode Detection

- **Create** — user wants a new document (default when no existing file is referenced)
- **Update** — user references an existing file to modify

## Steps

### 1. Detect schema

Run the schema detection script to discover valid frontmatter field values:

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/detect-schema.sh
```

This returns JSON with the schema file path and valid field values (e.g., valid `type`, `domain`, `tags` values). If no schema is found, the output will have empty fields — proceed without constrained values.

### 2. Confirm with user

Use `AskUserQuestion` to confirm:

- **Create mode**: proposed filename, location, title, and document type
- **Update mode**: the target file and what changes to make

Show the detected schema file (if any) so the user can verify it is the right one.

### 3. Write the document

- **Create**: Write a new markdown file with YAML frontmatter containing all required fields (`title`, `date` in YYYY-MM-DD format) and any constrained fields from the schema. Use the conversation context to populate the document body.
- **Update**: Read the existing file, apply the requested changes, and preserve existing frontmatter fields.

### 4. Validate frontmatter

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/validate-frontmatter.sh <file>
```

If validation fails (exit 1), fix the reported issues and re-validate.

### 5. Lint

If `rumdl` is available, run it with auto-fix:

```bash
rumdl check --fix <file>
```

If the file was modified by the linter, re-run `validate-frontmatter.sh` to ensure fixes didn't break frontmatter. If `rumdl` is not installed, skip linting and inform the user.

### 6. Offer to commit

Use `AskUserQuestion` to ask whether to commit and push the changes. **Never auto-commit.** If the user agrees, stage the file and commit with a descriptive message.

## Rules

- Always use `detect-schema.sh` output to constrain frontmatter values — do not guess valid values.
- Date fields must use YYYY-MM-DD format.
- Tags should be YAML flow sequences: `tags: [tag1, tag2]`.
- If the schema defines constrained fields (type, domain, status, tags), only use values from the schema output.
- Run validation and linting on every write, even updates.
