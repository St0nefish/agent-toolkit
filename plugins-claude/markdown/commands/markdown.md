---
description: "Markdown linting and formatting — check, format, setup"
argument-hint: "[action]"
allowed-tools: Bash
disable-model-invocation: true
---

# Markdown

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `check`, `format`, `setup`. Usage: `/markdown [action]`)

---

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
- Use `/markdown format` to auto-fix violations
- If rumdl is not found, run `/markdown setup`

---

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
- If rumdl is not found, run `/markdown setup`

---

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
