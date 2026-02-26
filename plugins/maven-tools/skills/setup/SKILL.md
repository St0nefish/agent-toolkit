---
name: maven-tools-setup
description: >-
  Pull the maven-tools Docker image. Run this once before using the maven-tools
  MCP server. Use when the user wants to set up or update maven-tools.
disable-model-invocation: true
allowed-tools: Bash
---

# Maven Tools Setup

Pull the Docker image for the maven-tools MCP server.

## Install

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

## Teardown

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
