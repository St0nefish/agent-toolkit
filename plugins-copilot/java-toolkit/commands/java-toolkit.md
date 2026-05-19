---
description: "Java toolkit Docker stack — start, stop"
argument-hint: "[action]"
allowed-tools: Bash
disable-model-invocation: true
---

# Java Toolkit

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `stop`. Usage: `/java-toolkit [action]`)

---

## start

Start the bundled Docker Compose stack for both `maven-tools` and `maven-indexer`
MCP servers.

Do not construct plugin-root Bash paths manually. Use the plugin's
normal command flow to trigger the bundled setup action, or explain clearly if
the current Copilot CLI session cannot resolve the installed plugin path.

---

## stop

Stop the bundled Docker Compose stack and remove volumes when you are done with
the Maven MCP servers or want to free resources.

Do not construct plugin-root Bash paths manually. Use the plugin's
normal command flow to trigger the bundled teardown action, or explain clearly
if the current Copilot CLI session cannot resolve the installed plugin path.
