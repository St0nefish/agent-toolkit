# Maven Tools MCP Server

Maven Central intelligence for Claude Code: versions, CVEs, dependency health,
and documentation lookups. Runs stateless via `docker run --rm -i` (no compose
needed).

## Quick Start

```bash
# Pull the image and configure Claude Code
./setup.sh --global

# Or configure for a specific project
./setup.sh --project /path/to/repo
```

## Manual Setup

```bash
# Pull the image
docker pull arvindand/maven-tools-mcp:2.0.2-noc7

# Add to Claude Code manually (see sample-mcp-config.json)
claude mcp add --scope user --transport stdio maven-tools \
    -- docker run --rm -i arvindand/maven-tools-mcp:2.0.2-noc7
```

## Image Tag: noc7

The `-noc7` image variant disables Context7 (documentation service) integration.
Context7 requires an enterprise license and its upstream backend currently
returns `text/plain` instead of SSE, causing crash loops in the standard image.
The `-noc7` variant avoids this issue entirely.

If Context7 becomes stable or you have a license, you can switch to the standard
tag (e.g., `2.0.2`).

## Management

```bash
./setup.sh --status   # Show image info and MCP server status
./setup.sh --down     # Remove MCP config
```

## Tools Available

- `get_latest_version` — latest version of a Maven artifact
- `check_version_exists` — verify a specific version exists
- `compare_dependency_versions` — compare versions across artifacts
- `analyze_project_health` — health metrics for a Maven artifact
