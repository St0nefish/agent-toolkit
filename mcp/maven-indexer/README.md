# Maven Indexer MCP Server

Indexes Gradle and Maven caches for class search and CFR decompilation. Runs as
a persistent Docker Compose service with a SQLite index. Claude Code connects
via STDIO through `docker exec -i`.

## Quick Start

```bash
# Start the server and configure Claude Code
./setup.sh --global

# Or configure for a specific project
./setup.sh --project /path/to/repo

# Watch initial indexing (first run takes a minute)
docker compose logs -f maven-indexer
```

## Manual Setup

```bash
# Start the compose stack
docker compose up -d

# Add to Claude Code manually (see sample-mcp-config.json)
claude mcp add --scope user --transport stdio maven-indexer \
    -- docker exec -i mcp-maven-indexer npx -y maven-indexer-mcp@latest
```

## Customization

### Filtering indexed packages

To only index specific packages (e.g. internal company libraries), set
`INCLUDED_PACKAGES` in the compose file:

```yaml
environment:
    - INCLUDED_PACKAGES=com.yourcompany.*,org.internal.*
```

### Custom cache locations

Override with environment variables before running compose:

```bash
GRADLE_CACHE=/path/to/gradle/cache MAVEN_REPO=/path/to/m2/repo docker compose up -d
```

## Management

```bash
./setup.sh --status   # Show compose and MCP server status
./setup.sh --down     # Stop compose stack and remove MCP config
```

## Tools Available

- `search_classes` — find classes by name across all indexed artifacts
- `get_class_details` — decompile a class using CFR
- `search_artifacts` — find artifacts by group/artifact ID
- `search_implementations` — find implementations of an interface
- `refresh_index` — re-index the caches
