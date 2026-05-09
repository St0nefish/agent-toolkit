---
disable-model-invocation: true
name: maven-indexer
description: "Maven indexer Docker stack — start, stop"
argument-hint: "[action]"
allowed-tools: Bash
---

# Maven Indexer

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `stop`. Usage: `/maven-indexer [action]`)


## start

Start the Docker Compose stack for the maven-indexer MCP server. Run this before using the maven-indexer MCP server tools (search_classes, get_class_details, etc.).

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```


## stop

Stop the Docker Compose stack and remove volumes. Use when done with class search/decompilation or to free resources.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
