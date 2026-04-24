---
user-invocable: false
name: ast-grep
description: >-
  Use for structural code search and bulk refactoring using AST patterns — when
  the task is finding or transforming code by its syntax shape rather than its
  text. Use instead of grep/ripgrep when matching nested expressions, calls with
  specific argument shapes, or patterns that span multiple tokens where regex
  would be fragile. Use for bulk refactors that match a code pattern across many
  files (e.g. "find all calls to foo.bar(x) where x is a string literal",
  "replace all usages of deprecated API X with Y"). Do NOT use for plain text
  search (use grep/rg instead). Do NOT use for symbol rename or reference
  lookup — use Serena LSP tools (rename_symbol, find_referencing_symbols) instead.
allowed-tools: Bash
---

# ast-grep — Structural Code Search and Rewrite

`ast-grep` matches code by its AST structure, not by text. It understands syntax, so wildcards match real syntax nodes (expressions, identifiers, argument lists) rather than arbitrary text spans.

**Binary:** `ast-grep` (not `sg` — `sg` is shadowed by a system utility on Linux)

## Core invocation

```bash
ast-grep run --pattern '<PATTERN>' --lang <LANG> [PATH...]
```

All three parts are required for most searches: `--pattern`, `--lang`, and a path (defaults to `.`).

## Key flags

| Flag | Short | Purpose |
|------|-------|---------|
| `--pattern` | `-p` | AST pattern to match |
| `--rewrite` | `-r` | Replacement string (uses `$VAR` from pattern) |
| `--lang` | `-l` | Language (required) |
| `--json` | | Output matches as JSON |
| `--json=stream` | | Output one JSON object per line (pipe-friendly) |
| `--context` | `-C` | Show N lines of context around each match |

## Wildcard syntax

| Wildcard | Matches |
|----------|---------|
| `$VAR` | Any single AST node (expression, identifier, call, etc.) |
| `$$$VAR` | Zero or more nodes (argument lists, statement sequences) |
| `$_` | Any single node, unnamed (throwaway) |
| `$$$` | Any sequence of nodes, unnamed |

## Language names

Common values for `--lang`: `python`, `javascript`, `typescript`, `java`, `kotlin`, `rust`, `go`, `ruby`, `c`, `cpp`, `bash`, `json`, `yaml`.

Full list: <https://ast-grep.github.io/reference/languages.html>

## Examples

### Search — find all calls to a function

```bash
# Find all calls to console.log with any arguments
ast-grep run --pattern 'console.log($$$ARGS)' --lang javascript src/

# Find all usages of a deprecated method
ast-grep run --pattern '$OBJ.oldMethod($$$ARGS)' --lang kotlin .
```

### Search with JSON output (for scripting)

```bash
ast-grep run --pattern 'foo($X, $Y)' --lang python --json=stream src/
```

### Search with context

```bash
ast-grep run --pattern 'throw new $ERR($$$)' --lang java -C 3 src/
```

### Rewrite — bulk structural refactor

```bash
# Rename a function call, preserving arguments
ast-grep run --pattern 'oldFunction($$$ARGS)' --rewrite 'newFunction($$$ARGS)' --lang python .

# Add a missing argument
ast-grep run --pattern 'createUser($NAME)' --rewrite 'createUser($NAME, defaultRole)' --lang typescript src/
```

## When NOT to use ast-grep

- **Plain text or string search** — use `grep` or `rg` (ripgrep). Faster and simpler for non-structural patterns.
- **Symbol rename across a codebase** — use Serena's `rename_symbol` (LSP-aware, handles imports and cross-file references).
- **Finding all references to a symbol** — use Serena's `find_referencing_symbols`.
- **Simple file content checks** — use `grep`/`rg`.

## Dry run before rewriting

Always run the search without `--rewrite` first to review matches, then add `--rewrite` once the pattern looks correct.

```bash
# Step 1: preview matches
ast-grep run --pattern 'OldApi.$METHOD($$$ARGS)' --lang java src/

# Step 2: apply rewrite
ast-grep run --pattern 'OldApi.$METHOD($$$ARGS)' --rewrite 'NewApi.$METHOD($$$ARGS)' --lang java src/
```

## Verifying installation

Run `/ast-grep:setup` to check if `ast-grep` is installed and print its version. Install via `cargo install ast-grep --locked` if missing.
