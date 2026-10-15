---
user-invocable: true
name: kb-capture
description: >-
  Capture conversation findings as schema-valid markdown. Triggers on
  "document this", "write this up", "capture this", "save to KB",
  "update the doc". Creates new files or updates existing ones.
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# KB Capture

Automate the research-to-document workflow: detect the knowledge base schema, write schema-valid markdown with frontmatter, lint, and commit.

## Mode Detection

- **Create** — user wants a new document (default when no existing file is referenced)
- **Update** — user references an existing file to modify

## Steps

### 1. Detect schema

Run the schema detection script to discover valid frontmatter field values:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-schema.sh
```

This returns JSON with the schema file path and valid field values (e.g., valid `type`, `domain`, `tags` values). If no schema is found, the output will have empty fields — proceed without constrained values.

### 2. State the plan

State, then proceed (use `AskUserQuestion` only when the target is genuinely ambiguous):

- **Create mode**: proposed filename, location, title, and document type
- **Update mode**: the target file and what changes to make

Name the detected schema file (if any).

### 3. Write the document

- **Create**: Write a new markdown file with YAML frontmatter containing all required fields (`title`, `date` in YYYY-MM-DD format) and any constrained fields from the schema. Use the conversation context to populate the document body.
- **Update**: Read the existing file, apply the requested changes, and preserve existing frontmatter fields.

### 4. Validate frontmatter

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-frontmatter.sh <file>
```

If validation fails (exit 1), fix the reported issues and re-validate.

### 5. Lint

If `rumdl` is available, run it with auto-fix:

```bash
rumdl check --fix <file>
```

If the file was modified by the linter, re-run `validate-frontmatter.sh` to ensure fixes didn't break frontmatter. If `rumdl` is not installed, skip linting and inform the user.

### 6. Commit

Stage the file and commit with a descriptive message, then push through the repo's normal pipeline (a PR via `/git-tools:ship` when the repo is PR-gated).

## Rules

- Always use `detect-schema.sh` output to constrain frontmatter values — do not guess valid values.
- Date fields must use YYYY-MM-DD format.
- Tags should be YAML flow sequences: `tags: [tag1, tag2]`.
- If the schema defines constrained fields (type, domain, status, tags), only use values from the schema output.
- Run validation and linting on every write, even updates.
