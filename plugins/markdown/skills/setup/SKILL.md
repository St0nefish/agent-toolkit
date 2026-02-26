---
name: markdown-setup
description: >-
  Install rumdl for markdown linting and formatting.
  Use when rumdl is not found or the user wants to set up the markdown plugin.
disable-model-invocation: true
allowed-tools: Bash
---

# Markdown Setup

Install [rumdl](https://github.com/sysid/rumdl), the Rust markdown linter and formatter.

## Check if installed

```bash
command -v rumdl && rumdl --version
```

## Install

**Via Cargo (all platforms):**

```bash
cargo install rumdl
```

**Via Homebrew (macOS):**

```bash
brew install rumdl
```

After installing, verify with `rumdl --version`.
