---
name: java-toolkit-setup
description: >-
  Start or stop the java-toolkit Docker Compose stack. Run start before using
  the maven-tools or maven-indexer MCP servers, and stop when done.
disable-model-invocation: true
allowed-tools: Bash
---

# Java Toolkit Setup

Manage the Docker Compose stack for the `java-toolkit` MCP servers.

## Start

Start the bundled Docker Compose stack using the plugin's normal setup flow.
Do not construct plugin-root Bash paths manually; if the current
Copilot CLI session cannot resolve the installed plugin path, say so plainly
instead of guessing.

## Stop

Stop the bundled Docker Compose stack using the plugin's normal teardown flow.
Do not construct plugin-root Bash paths manually; if the current
Copilot CLI session cannot resolve the installed plugin path, say so plainly
instead of guessing.
