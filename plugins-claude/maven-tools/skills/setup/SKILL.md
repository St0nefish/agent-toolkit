---
name: maven-tools-setup
description: >-
  Start or stop the maven-tools Docker Compose stack. Run start before using the
  maven-tools MCP server, and stop when done.
disable-model-invocation: true
allowed-tools: Bash
---

# Maven Tools Setup

Manage the Docker Compose stack for the maven-tools MCP server.

## Start

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

## Stop

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
