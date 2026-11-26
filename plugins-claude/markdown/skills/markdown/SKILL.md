---
disable-model-invocation: true
name: markdown
description: "Lint markdown with rumdl (check), auto-fix violations in place (format), or install rumdl (setup)."
when_to_use: "Use when the user wants markdown files, a directory, or the repo checked or fixed against .rumdl.toml, or when rumdl is missing."
argument-hint: "[check|format|setup]"
allowed-tools: Bash
---

# Markdown

Requested action: `$ARGUMENTS`. If it names an action below, run it. If it is empty, list the available actions (`check`, `format`, `setup`) with usage `/markdown:markdown [check|format|setup]` and ask which to run.

## check

Lint markdown files for style violations using [rumdl](https://github.com/sysid/rumdl).

### Usage

Check a single file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check README.md
```

Check all markdown in a directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check docs/
```

Check everything in the repo:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check .
```

### Notes

- Read-only, safe for auto-approval
- Respects `.rumdl.toml` config in the project
- Exit code 0 = no violations, non-zero = violations found
- Use `/markdown:markdown format` to auto-fix violations
- If rumdl is not found, run `/markdown:markdown setup`

## format

Auto-fix markdown lint violations using [rumdl](https://github.com/sysid/rumdl).

### Usage

Fix a single file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix README.md
```

Fix all markdown in a directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix docs/
```

Fix everything in the repo:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rumdl-wrap check --fix .
```

### Notes

- Modifies files in-place — only run on files you intend to change
- Respects `.rumdl.toml` config in the project
- Not all rules are auto-fixable — check output for remaining violations
- Exit code 0 = all fixed or clean, non-zero = unfixable violations remain
- If rumdl is not found, run `/markdown:markdown setup`

## setup

Install [rumdl](https://github.com/sysid/rumdl), the Rust markdown linter and formatter.

### Check if installed

```bash
command -v rumdl && rumdl --version
```

### Install

**Via Cargo (all platforms):**

```bash
cargo install rumdl
```

**Via Homebrew (macOS):**

```bash
brew install rumdl
```

After installing, verify with `rumdl --version`.
