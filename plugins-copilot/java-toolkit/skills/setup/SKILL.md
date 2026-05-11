---
name: java-toolkit-setup
description: >-
  Start or stop the java-toolkit Docker Compose stack. Run start before using
  the maven-tools or maven-indexer MCP servers, and stop when done.
disable-model-invocation: true
allowed-tools: Bash
---

# Java Toolkit Setup

Manage the Docker Compose stack for the java-toolkit MCP servers.

## Start

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/setup.sh
```

## Stop

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
