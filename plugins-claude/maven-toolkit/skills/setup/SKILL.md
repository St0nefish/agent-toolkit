---
name: maven-toolkit-setup
description: >-
  Start or stop the maven-toolkit Docker Compose stack. Run start before using the
  maven-toolkit MCP servers, and stop when done.
disable-model-invocation: true
allowed-tools: Bash
---

# Maven Toolkit Setup

Manage the Docker Compose stack for the maven-toolkit MCP servers.

## Start

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

## Stop

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
