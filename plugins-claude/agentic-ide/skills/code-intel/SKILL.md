---
user-invocable: false
name: code-intel
description: >-
  Pick the right code-intelligence tool and avoid its pitfalls. Use when
  planning symbol navigation, refactor, rename, structural search, bulk
  rewrite, security audit, or dataflow analysis — and before calling any
  `mcp__serena__*`, `mcp__semgrep__*`, or `ast-grep` command. Routes by
  intent, documents tool-specific quirks, points to the `agentic-ide:setup`
  skill when tools are missing.
---

# Code-intel routing and pitfalls

The `agentic-ide` plugin bundles three orthogonal tools. This skill is the routing hub **and** the cheatsheet — pick the right tool, then read the section for that tool before calling it.

## Decision table

| Intent | Tool | Entry point |
|--------|------|-------------|
| Find / read a symbol by name | Serena | `mcp__serena__find_symbol` |
| File outline (classes, methods) | Serena | `mcp__serena__get_symbols_overview` |
| Find callers / references | Serena | `mcp__serena__find_referencing_symbols` |
| Rename across files | Serena | `mcp__serena__rename_symbol` |
| Replace a symbol's body | Serena | `mcp__serena__replace_symbol_body` (⚠ doc-comment hazard) |
| Insert / delete a symbol | Serena | `insert_after_symbol`, `safe_delete_symbol` |
| Match code by AST shape | ast-grep | `ast-grep run --pattern ... --lang ...` |
| Bulk syntactic rewrite | ast-grep | add `--rewrite` |
| Security audit / vulnerability scan | Semgrep | `mcp__semgrep__security_check` |
| Trace tainted input to a sink | Semgrep | `mcp__semgrep__semgrep_scan` (taint mode) |
| Custom semantic rule | Semgrep | `mcp__semgrep__semgrep_scan_with_custom_rule` |
| Count occurrences of a literal | `grep -c` | built-in |
| Plain text search | `rg` / `grep` | built-in |
| Read a whole file | `Read` | built-in |

### Rule of thumb

- **Symbol-aware** (knows what a name means) → **Serena**
- **Syntax-aware** (knows the shape of code) → **ast-grep**
- **Semantic-aware** (knows types and dataflow) → **Semgrep**
- **Text-aware** (everything else) → **grep / rg / Read**

Serena's manual marks `Read` and `Edit` "FORBIDDEN" — overzealous. Use them for full-file reads, configs, tests-as-a-whole, and string/comment searches.

## Tool not installed?

If `mcp__serena__*` tools are unavailable, `semgrep-mcp` is missing, or `ast-grep` returns "command not found" — tell the user:

> "{Tool} isn't installed. Run `/agentic-ide:setup` to set it up."

Don't install yourself — the setup skill walks the user through it.

---

## Serena pitfalls

Quirks not in Serena's docs. Read before reaching for `mcp__serena__*`.

### Symbol path syntax

`name_path` matches the symbol tree within a file. Conventions vary:

| Language | Pattern | Example |
|----------|---------|---------|
| Python | `Class/method` | `MyClass/__init__` |
| Java | `Class/method[i]` (overload index) | `MyClass/format[1]` |
| **Rust** | **`impl Type/method`** | `impl App/select_next` |

**Rust gotcha:** the `impl` prefix is required. `App/select_next` returns empty; `impl App/select_next` works. Surfaces only from `name_path` in `find_referencing_symbols` output.

Free functions and types are bare: `find_symbol("run_compose")`, `find_symbol("ComposeCmd")`.

### All line numbers are 0-based

Every line Serena emits — `body_location`, `content_around_reference`, `safe_delete_symbol` refusal output — is **0-based**. Everything else (grep, compiler errors, your editor, git blame) is 1-based. Add 1 when cross-referencing.

### `replace_symbol_body` deletes doc comments

**Highest-impact pitfall.** `find_symbol` with `include_body=true` returns the body **without** preceding doc comments — but `replace_symbol_body`'s write scope **does** include them. A round-trip (read → write back) silently destroys rustdoc / docstrings / `///` blocks.

Before calling: check for preceding doc comments and include them in the new body string. Verify with `git diff` after every write.

### `rename_symbol` is identifier-aware

LSP-driven, so it crosses files and respects identifier boundaries:

- Updates `print_summary` wherever it's used as a complete identifier
- Does **not** touch `print_summary_to`, `test_print_summary_*`, string literals, or comments

Always follow up with `grep -rn '<old_name>'` and a typecheck. Test names and rustdoc references usually need a manual pass. The returned "N changes applied" counts **files modified**, not sites updated.

### Memory tools are disabled

`write_memory` / `read_memory` / `list_memories` / onboarding are disabled in the recommended install. Project context lives in `CLAUDE.md`, `README.md`, `.serena/project.yml`. The memory tools won't appear in the tool list.

### Heavy Serena meta-analysis → `serena-explorer`

For "blast radius of renaming X", "call graph N hops out", "group symbols by criterion" — spawn the **`serena-explorer`** subagent (this plugin). It absorbs Serena's verbose JSON in its own context and returns a concise synthesis. Read-only.

---

## ast-grep — structural search and rewrite

Matches code by AST structure, not text. Wildcards match real syntax nodes (expressions, identifiers, argument lists), not arbitrary text spans.

**Binary:** `ast-grep` (not `sg` — `sg` is shadowed by a system utility on Linux).

### Invocation

```bash
ast-grep run --pattern '<PATTERN>' --lang <LANG> [PATH...]
```

`--pattern`, `--lang`, and a path are all required (path defaults to `.`).

### Wildcards

| Wildcard | Matches |
|----------|---------|
| `$VAR` | One AST node (named, captures for reuse in `--rewrite`) |
| `$$$VAR` | Zero or more nodes (argument lists, statement sequences) |
| `$_` / `$$$` | Same, unnamed (throwaway) |

### Useful flags

| Flag | Purpose |
|------|---------|
| `-r / --rewrite` | Replacement string; reuses `$VAR` captures |
| `--json=stream` | One JSON object per line (pipe-friendly) |
| `-C / --context N` | N lines of context per match |

### Examples

```bash
# Find all calls to a deprecated method
ast-grep run --pattern '$OBJ.oldMethod($$$ARGS)' --lang kotlin .

# Bulk rename a function, preserving arguments
ast-grep run --pattern 'oldFn($$$ARGS)' --rewrite 'newFn($$$ARGS)' --lang python .
```

Always run without `--rewrite` first to review matches.

### Languages

Common: `python`, `javascript`, `typescript`, `java`, `kotlin`, `rust`, `go`, `ruby`, `c`, `cpp`, `bash`, `json`, `yaml`. Full list: <https://ast-grep.github.io/reference/languages.html>.

---

## Semgrep — security and dataflow

Semgrep understands **types and dataflow**, not just syntax. That's the reason to reach for it over `ast-grep` or `grep`.

### Tools

| Tool | Purpose |
|------|---------|
| `security_check` | Curated default security ruleset — start here |
| `semgrep_scan` | Scan with a registry config (e.g. `p/owasp-top-ten`) or local path |
| `semgrep_scan_with_custom_rule` | One-shot scan with an inline YAML rule |
| `semgrep_findings` | Fetch findings from Semgrep AppSec Platform (needs `SEMGREP_APP_TOKEN`) |
| `get_abstract_syntax_tree`, `supported_languages`, `semgrep_rule_schema` | Metadata helpers |

### Registry shortcuts for `semgrep_scan`

- `auto` — language-detected default
- `p/security-audit`, `p/owasp-top-ten`, `p/secrets`
- `p/python`, `p/javascript`, `p/java`, `p/go`, ...

Full registry: <https://semgrep.dev/explore>

### Custom rules

Minimal pattern rule:

```yaml
rules:
  - id: no-eval
    pattern: eval(...)
    message: "Avoid eval()."
    languages: [python]
    severity: WARNING
```

Taint rule (source → sink):

```yaml
rules:
  - id: tainted-sql
    mode: taint
    pattern-sources:
      - pattern: request.args.get(...)
    pattern-sinks:
      - pattern: cursor.execute($SQL, ...)
    message: "User input flows into SQL execute()."
    languages: [python]
    severity: ERROR
```

Pass the rule body as `custom_rule` to `semgrep_scan_with_custom_rule`.

### Bounding output

Findings can be large — each entry carries rule metadata, location, and surrounding context. Scope `path` to a subtree and prefer `security_check` over `p/security-audit` for first passes.
