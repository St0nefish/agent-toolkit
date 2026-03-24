# Maven Indexer

MCP server for class search and decompilation in local Gradle and Maven caches. Runs as a persistent Docker Compose service that indexes your dependency caches into a SQLite database.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/maven-indexer
```

Then start the service:

```text
/maven-indexer start
```

## How It Works

Runs `maven-indexer-mcp@latest` (Node 22) inside a Docker container. Claude Code connects via `docker exec` STDIO. The container mounts your local `~/.gradle` and `~/.m2` caches read-only and builds a persistent SQLite index.

## MCP Tools

| Tool | Description |
|------|-------------|
| `search_classes` | Find classes by name across all cached artifacts |
| `get_class_details` | Decompile a class using CFR |
| `search_artifacts` | Search artifacts by group/artifact ID |
| `search_implementations` | Find implementations of an interface or class |

## Commands

| Command | Description |
|---------|-------------|
| `/maven-indexer start` | Start the Docker Compose service |
| `/maven-indexer stop` | Stop and remove the service |

## Configuration

Environment variables in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `INCLUDED_PACKAGES` | `*` | Filter which packages to index |
| `VERSION_RESOLUTION_STRATEGY` | `semver` | `semver`, `latest-published`, or `latest-used` |

Cache path overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `GRADLE_CACHE` | `~/.gradle/caches/modules-2/files-2.1` | Gradle cache location |
| `MAVEN_REPO` | `~/.m2/repository` | Maven cache location |
| `SDKMAN_DIR` | `~/.sdkman` | SDKMAN location (for JDK used by CFR decompiler) |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| Docker | Yes | Container runtime |
| Docker Compose | Yes | Service orchestration |
| JDK (via SDKMAN) | For decompilation | CFR decompiler needs a JDK |
