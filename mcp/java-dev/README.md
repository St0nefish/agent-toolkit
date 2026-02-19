# Java Development MCP Servers

Headless MCP servers for Java dependency analysis with Claude Code. Complements
IntelliJ IDEA's built-in MCP server (which handles project source operations but
cannot inspect external dependencies).

## What's Included

| Server | Purpose | Transport |
|--------|---------|-----------|
| **maven-indexer-mcp** | Index Gradle + Maven caches, search classes, CFR decompilation | STDIO |
| **maven-tools-mcp** | Maven Central intelligence: versions, CVEs, health, docs | Streamable HTTP |

## Quick Start

```bash
# Start the servers
docker compose up -d

# Watch initial indexing (first run takes a minute)
docker compose logs -f maven-indexer

# Configure Claude Code (pick docker-compose entries from sample config)
# See sample-mcp-config.json for all options
```

## Configuration

See `sample-mcp-config.json` for Claude Code MCP configuration examples. There
are two variants per server:

- **Docker Compose**: servers run persistently, Claude Code connects to them
- **Direct**: Claude Code spawns the process on demand (simpler, slower startup)

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

### Restricted networks

If Context7 (documentation service) is blocked by corporate firewall, swap the
maven-tools image tag to the `-noc7` variant in docker-compose.yml.

## Full Documentation

See the knowledge base doc for the complete research, comparison, and rationale:
`knowledge-base/dev/tools/java-mcp-servers.md`
