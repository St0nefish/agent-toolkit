# Java Toolkit

Java/JVM tooling — Maven Central intelligence and class search/decompilation via an MCP server running in Docker, plus a `jar-explore` script for raw JAR content inspection.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/java-toolkit
```

Then start the Docker stack before using the MCP servers:

```bash
/java-toolkit:setup start
```

## How It Works

Two MCP servers run as persistent Docker containers and communicate with Claude Code over `docker exec -i`:

| Server | Container | Purpose |
|--------|-----------|---------|
| `maven-tools` | `mcp-maven-tools` | Maven Central artifact search, dependency resolution, and version intelligence |
| `maven-indexer` | `mcp-maven-indexer` | Class search by name, source decompilation via CFR, interface implementation lookup |

`maven-indexer` mounts your local Gradle and Maven caches read-only so it can index and decompile JARs you've already downloaded without re-fetching them. A SQLite index persists between restarts in a named Docker volume.

## Skills

| Skill | Type | Description |
|-------|------|-------------|
| `jar-explore` | Model-triggered | List, search, and read files inside JARs (manifests, `.properties`, XML, resources) without extracting to disk — use instead of `jar tf` / `unzip` |
| `/java-toolkit:setup` | User-invoked | Start or stop the Docker Compose stack (`start` / `stop`) |
| `/java-toolkit:java-toolkit` | User-invoked | Alias for managing the Docker stack |

## jar-explore

The `jar-explore` script covers what the MCP server doesn't: listing raw JAR entries, regex search within a JAR, and reading arbitrary non-class files. Use the MCP server for class-level work (search, decompile, find implementations).

```bash
# List all entries
${CLAUDE_PLUGIN_ROOT}/scripts/jar-explore list /path/to/file.jar

# Search for entries matching a pattern (case-insensitive extended regex)
${CLAUDE_PLUGIN_ROOT}/scripts/jar-explore search /path/to/file.jar "META-INF.*\.properties"

# Read a file from a JAR without extracting to disk
${CLAUDE_PLUGIN_ROOT}/scripts/jar-explore read /path/to/file.jar META-INF/MANIFEST.MF
```

## Docker Stack Management

```bash
/java-toolkit:setup start   # docker compose up -d (both containers)
/java-toolkit:setup stop    # docker compose down -v (removes volumes)
```

The `docker-compose.yml` is bundled in the plugin. On first start it pulls `arvindand/maven-tools-mcp:2.0.2-noc7` and `node:22-slim`. Subsequent starts are instant.

### Volume mounts

`maven-indexer` mounts the following paths read-only at startup:

| Host path | Purpose |
|-----------|---------|
| `~/.gradle/caches/modules-2/files-2.1` | Gradle artifact cache |
| `~/.m2/repository` | Maven local repository |
| `~/.sdkman/candidates/java/current` | SDKMAN-managed JDK for CFR decompilation |

Override any of these with `GRADLE_CACHE`, `MAVEN_REPO`, or `SDKMAN_DIR` environment variables.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `docker` | Yes | Run the MCP server containers |
| Docker Compose | Yes | Manage the multi-container stack (bundled with Docker Desktop; `docker compose` plugin for standalone) |
