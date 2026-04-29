---
user-invocable: false
name: serena-cheatsheet
description: >-
  Quirks, conventions, and pitfalls for the Serena MCP server. Use whenever
  calling any `mcp__serena__*` tool — `find_symbol`, `find_referencing_symbols`,
  `get_symbols_overview`, `replace_symbol_body`, `insert_after_symbol`,
  `rename_symbol`, `safe_delete_symbol`, `replace_content`. Also use when
  planning code navigation, refactors, or rename operations on a project that
  has Serena active. Covers Rust impl-method syntax, 0-based line numbers, the
  `replace_symbol_body` doc-comment hazard, identifier-aware rename semantics,
  and verbosity controls.
---

# Serena cheatsheet

Serena exposes language-server-driven code intelligence over MCP. It's
genuinely better than grep for symbol-aware operations — but it has sharp
edges that aren't in the official docs. This skill documents them.

## Symbol path syntax

`name_path` matches the symbol tree *within a source file*. Conventions vary
by language:

| Language | Pattern | Example |
|----------|---------|---------|
| Python | `Class/method` | `MyClass/__init__` |
| Java | `Class/method[i]` (overload index) | `MyClass/format[1]` |
| **Rust** | **`impl Type/method`** | `impl App/select_next_running` |

**Rust gotcha:** the `impl` prefix is required. Querying `App/select_next_running`
returns empty even though the method exists. This is not in Serena's docs — it
only surfaces from the `name_path` field in `find_referencing_symbols` output.

Free functions and types are bare:

- `find_symbol("ComposeCmd")` — returns the enum
- `find_symbol("run_compose")` — returns the free function

## Line numbers are 0-based

Every line number Serena emits — in `body_location`, `content_around_reference`,
or `safe_delete_symbol` refusal output — is **0-based**. Everything else
(grep, `cargo` errors, your editor, git blame) is 1-based.

When cross-referencing with other tools, add 1.

## `replace_symbol_body` silently deletes doc comments

**This is the highest-impact pitfall.** Reading a symbol via `find_symbol` with
`include_body=true` returns the body *without* preceding doc comments — the docs
explicitly state this. But `replace_symbol_body`'s replacement scope **does**
include the doc comment. So a "round-trip" replace (read body → write body
back) silently destroys any rustdoc, Python docstring before a function (in
some languages), or `///`-style comment block.

**Before calling `replace_symbol_body`:**

1. Check whether the target has preceding doc comments (read the file or check
   surrounding context).
2. If so, **include the doc comment as part of your new body string.** The
   write operation needs to reproduce them or they're gone.

Verify with `git diff` after every `replace_symbol_body` call.

## `rename_symbol` is identifier-aware (not text-aware)

This is the biggest win over grep-based rename. `rename_symbol` updates the
target identifier across the codebase via the language server, so:

- ✅ Updates `print_summary` everywhere it's used as a complete identifier
- ✅ Crosses files (use statements, call sites, imports)
- ❌ Does **not** touch `print_summary_to` (different identifier)
- ❌ Does **not** rename `test_print_summary_*` test functions
- ❌ Does **not** update string literals or comments mentioning the name

Always verify with two checks:

```bash
grep -rn '<old_name>' src/   # any survivors?
cargo check                  # or your language's typecheck
```

Test function names and rustdoc references usually need a follow-up pass.

The "N changes applied" return count is **files modified**, not sites updated.

## `safe_delete_symbol` returns 0-based references on refusal

When a symbol still has references, `safe_delete_symbol` refuses and returns:

```json
{"src/runner.rs": [390, 405], "src/main.rs": [21, 291]}
```

These are 0-based line numbers. Add 1 to match grep / editor output.

## Verbosity control

`find_referencing_symbols` is verbose — every reference in a match arm or
repeated test call gets its own entry with surrounding context. A query for a
heavily-used symbol can return 30KB+ of JSON.

Bound output up front:

| Param | Use case |
|-------|----------|
| `relative_path` | Restrict to one file/dir — single biggest reduction |
| `max_matches` | Cap result count; result indicates "more available" |
| `max_answer_chars` | Hard cap; returns nothing if exceeded (forces refinement) |

When you genuinely just want a count or simple list, **drop to `grep`**. Serena's
own instruction manual permits grep/glob for discovery — use them.

For verbose meta-analysis questions ("blast radius of renaming X", "call graph
of run_compose two levels deep"), spawn the **`serena-explorer`** subagent —
it absorbs the verbose output and returns a concise synthesis.

## Discovery preferences

Serena's instruction manual (loaded when its tools first activate) declares
`Read` and `Edit` "FORBIDDEN" for code files in favor of symbolic tools. In
practice this is mostly correct but situational:

- **Use Serena symbolic tools for**: targeted symbol reads, cross-file
  references, refactor-style edits (rename, delete, replace body, insert).
- **Use Read for**: full-file reads when you genuinely need surrounding
  context the symbolic tools strip out (e.g. understanding what's between
  two top-level functions, reading config/data files, reading tests as a
  whole).
- **Use grep/glob for**: pure counts, string-literal searches, comment
  searches, finding files by name.

The forbidden framing in Serena's manual is overzealous — judgment still
applies.

## Memories are disabled by config

This installation has Serena's memory tools (`write_memory`, `read_memory`,
`list_memories`, etc.) explicitly disabled. The onboarding flow is also
disabled.

Project context lives in source-controlled files (CLAUDE.md, README.md,
`.serena/project.yml`). Do not try to invoke memory tools — they will not
appear in the available tool list.

## Quick reference

| Want to | Tool |
|---------|------|
| See symbols in a file | `get_symbols_overview` |
| Read a symbol's body | `find_symbol` with `include_body=true` |
| Find callers / references | `find_referencing_symbols` |
| Rename across files | `rename_symbol` |
| Add code after a symbol | `insert_after_symbol` |
| Replace a symbol's definition | `replace_symbol_body` (⚠️ doc comments) |
| Delete an unreferenced symbol | `safe_delete_symbol` |
| Edit a few lines inside a symbol | `replace_content` (regex) |
| Count usages of a string | `grep -c` |
| Heavy meta-analysis | spawn `serena-explorer` agent |
