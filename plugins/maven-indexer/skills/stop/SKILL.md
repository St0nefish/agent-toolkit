---
name: maven-indexer-stop
description: >-
  Stop and remove the maven-indexer Docker Compose stack and volumes.
  Use when done with class search/decompilation or to free resources.
disable-model-invocation: true
allowed-tools: Bash
---

# Stop Maven Indexer

Stop the Docker Compose stack and remove volumes.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --teardown
```
