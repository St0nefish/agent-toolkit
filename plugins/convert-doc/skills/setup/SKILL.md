---
name: convert-doc-setup
description: >-
  Install pandoc for document conversion.
  Use when pandoc is not found or the user wants to set up the convert-doc plugin.
disable-model-invocation: true
allowed-tools: Bash
---

# Convert-Doc Setup

Install [pandoc](https://pandoc.org/), the universal document converter.

## Check if installed

```bash
command -v pandoc && pandoc --version
```

## Install

**macOS:**

```bash
brew install pandoc
```

**Linux (Debian/Ubuntu):**

```bash
sudo apt install pandoc
```

After installing, verify with `pandoc --version`.
