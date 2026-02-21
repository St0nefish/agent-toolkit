# mcp/ — MCP Server Definitions

Each subdirectory in `mcp/` defines one MCP server that can be registered into
Claude Code's `settings.json` (global) or a project's `.mcp.json` (project-scoped)
via `./deploy`.

See the root `CLAUDE.md` for full deployment config details, `--include`/`--exclude`,
profiles, and `--teardown-mcp`.

---

## How to Add a New MCP Server

### Step 1: Create the directory

```bash
mkdir mcp/<name>
```

Use a short, lowercase, hyphenated name matching how it will appear in `mcpServers`.

### Step 2: Create `deploy.json`

This is the only required file. It must contain an `"mcp"` key with either
`"command"` (stdio transport) or `"url"` (HTTP transport).

**Stdio — ephemeral Docker container (stateless):**

```json
{
  "mcp": {
    "command": "docker",
    "args": ["run", "--rm", "-i", "some-image:tag"],
    "env": {}
  }
}
```

**Stdio — persistent container via `docker exec` (stateful, needs compose):**

```json
{
  "mcp": {
    "command": "docker",
    "args": ["exec", "-i", "container-name", "npx", "-y", "some-mcp@latest"],
    "env": {}
  }
}
```

**Stdio — local command (no Docker):**

```json
{
  "mcp": {
    "command": "npx",
    "args": ["-y", "some-mcp-package@latest"],
    "env": {
      "API_KEY": "your-key-here"
    }
  }
}
```

**HTTP — hosted service (no local runtime):**

```json
{
  "mcp": {
    "url": "https://mcp.example.com/mcp"
  }
}
```

**HTTP — SSE transport (JetBrains IDE plugin, etc.):**

```json
{
  "enabled": false,
  "mcp": {
    "type": "sse",
    "url": "http://localhost:PORT/sse",
    "headers": {
      "SOME_HEADER": "value"
    }
  }
}
```

The `mcp` value is written verbatim into `mcpServers.<name>` in `settings.json`
or `.mcp.json`. Use `"enabled": false` to disable a server without removing it.

### Step 3: Add `setup.sh` (optional)

Required only when the server needs local prerequisites — pulling a Docker image,
starting a compose stack, etc. The deployer runs `setup.sh` (no args) before
registering the config. If `setup.sh` exits non-zero, the server is not registered.

**Template:**

```bash
#!/usr/bin/env bash
# setup.sh - Set up / tear down <name> MCP server
#
# Usage:
#   ./setup.sh              # Install / start
#   ./setup.sh --teardown   # Remove / stop
#
# MCP config registration is handled by deploy.py via deploy.json.

set -euo pipefail

die()  { echo "Error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"
}

require_cmd docker

case "${1:-}" in
    --teardown)
        info "Removing <name>..."
        # e.g.: docker rmi some-image:tag 2>/dev/null || true
        ;;
    "")
        info "Setting up <name>..."
        # e.g.: docker pull some-image:tag
        ;;
    *)
        die "Unknown option: $1 (use --teardown or no args)"
        ;;
esac
```

Make it executable: `chmod +x mcp/<name>/setup.sh`

### Step 4: Add `docker-compose.yml` (optional)

Only needed for servers that require a persistent container (not `docker run --rm`).
The compose file is managed by `setup.sh` — the deployer does not touch it directly.

```yaml
services:
  <name>:
    image: some-image:tag
    container_name: mcp-<name>
    restart: unless-stopped
    stdin_open: true          # required for STDIO transport via docker exec
    volumes:
      - <name>-data:/data     # persist state between restarts

volumes:
  <name>-data:
```

The `deploy.json` then connects via `docker exec -i mcp-<name> ...`.

### Step 5: Add `README.md` (optional but recommended)

Document what tools the server exposes, any required credentials, and any
management commands specific to the server.

### Step 6: Deploy

```bash
# Deploy globally (registers in ~/.claude/settings.json)
./deploy --include <name>

# Deploy to a specific project only
./deploy --include <name> --project /path/to/repo

# Preview without making changes
./deploy --dry-run --include <name>
```

---

## Directory Structure Reference

```
mcp/<name>/
  deploy.json          ← required: "mcp" key with server definition
  deploy.local.json    ← optional: user overrides (gitignored)
  setup.sh             ← optional: install / --teardown logic
  docker-compose.yml   ← optional: persistent container definition
  README.md            ← optional: usage docs (not deployed)
```

---

## Existing Servers (Examples)

| Directory | Transport | Runtime | Notes |
|-----------|-----------|---------|-------|
| `context7/` | HTTP | None (hosted) | URL-based, no local runtime needed |
| `idea/` | SSE/HTTP | JetBrains IDE | `deploy.local.json` per-user; disabled in `deploy.json` |
| `maven-tools/` | stdio | Docker (`run --rm`) | Stateless; `setup.sh` pulls image |
| `maven-indexer/` | stdio | Docker Compose + `exec` | Stateful SQLite index; `setup.sh` manages compose stack |

---

## How Deployment Works

1. `./deploy` discovers all `mcp/*/` directories.
2. For each directory it reads and merges `deploy.json` then `deploy.local.json`.
3. If `enabled` is `false` (or filtered by `--include`/`--exclude`), the server is skipped.
4. If a `setup.sh` is present and executable, it is run with no arguments. A
   non-zero exit skips config registration for that server.
5. The `"mcp"` object from the merged config is written verbatim into
   `mcpServers.<name>` in the target settings file:
   - Global deploy → `~/.claude/settings.json`
   - `--project PATH` → `PATH/.mcp.json`
6. Teardown: `./deploy --teardown-mcp <name>` runs `setup.sh --teardown` and
   removes the server from `mcpServers`.
