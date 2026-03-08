---
description: "Maven tools Docker stack — start, stop"
argument-hint: "[action]"
allowed-tools: Bash
disable-model-invocation: true
---

# Maven Tools

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `stop`. Usage: `/maven-tools [action]`)

---

## start

Start the Docker Compose stack for the maven-tools MCP server. Run this before using maven-tools MCP server functions.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

---

## stop

Stop the Docker Compose stack and remove volumes. Use when done with maven-tools MCP server usage or to free resources.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
