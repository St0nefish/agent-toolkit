---
disable-model-invocation: true
name: java-toolkit
description: >-
  Start or stop the java-toolkit Docker Compose stack behind the maven-tools and
  maven-indexer MCP servers.
when_to_use: >-
  Use when those MCP tools are unavailable or the user wants to bring the stack
  up, or when done with them to free resources (stop removes volumes).
argument-hint: "[start|stop]"
allowed-tools: Bash
---

# Java Toolkit

Requested action: `$ARGUMENTS`. If it names an action below, run it. If it is empty, list the available actions (`start`, `stop`) with usage `/java-toolkit:java-toolkit [start|stop]` and ask which to run.

## start

Start the Docker Compose stack for both maven-tools and maven-indexer MCP servers.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

## stop

Stop the Docker Compose stack and remove volumes. Use when done with MCP server usage or to free resources.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
