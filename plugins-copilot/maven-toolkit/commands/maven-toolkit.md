---
description: "Maven toolkit Docker stack — start, stop"
argument-hint: "[action]"
allowed-tools: Bash
disable-model-invocation: true
---

# Maven Toolkit

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `stop`. Usage: `/maven-toolkit [action]`)

---

## start

Start the Docker Compose stack for both maven-tools and maven-indexer MCP servers.

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/setup.sh
```

---

## stop

Stop the Docker Compose stack and remove volumes. Use when done with MCP server usage or to free resources.

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
