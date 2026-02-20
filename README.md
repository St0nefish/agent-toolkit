# Claude Toolkit

Reusable CLI tools, hooks, and MCP servers for Claude Code development workflows. Each component is self-contained and deployed via a single idempotent script.

## Structure

```
skills/
  <name>/                     ← one folder per skill
    bin/<script>              ← executable(s)
    <name>.md                 ← skill definition(s)
    deploy.json               ← optional: deployment config (tracked)
    deploy.local.json         ← optional: user overrides (gitignored)
hooks/
  <name>/                     ← one folder per hook
    <script>.sh              ← hook script(s)
    deploy.json               ← optional: deployment config (tracked)
    deploy.local.json         ← optional: user overrides (gitignored)
mcp/
  <name>/                     ← one folder per MCP server
    deploy.json               ← required: must contain "mcp" key
    setup.sh                  ← optional: install prereqs / teardown
    docker-compose.yml        ← optional: persistent containers
deploy-py/                    ← deployment tooling
  deploy.py                   ← idempotent deployment script
  deploy/                     ← deploy script internals
  pyproject.toml              ← Python project config and dev dependencies
  tests/                      ← pytest + bash test scripts
deploy                        ← convenience wrapper for deploy-py/deploy.py
deploy.json                   ← optional: repo-wide deployment config (tracked)
deploy.local.json             ← optional: user overrides (gitignored)
```

After deployment:

```
~/.claude/tools/<name>/        ← symlink to skills/<name>/
~/.claude/commands/<x>.md      ← symlink to individual skill .md files
~/.claude/hooks/<name>/        ← symlink to hooks/<name>/
~/.local/bin/<script>          ← optional (--on-path), for direct human use
settings.json mcpServers       ← MCP server definitions
```

## Tools

| Tool | Description |
|------|-------------|
| `jar-explore` | Inspect, search, and read files inside JARs — replaces raw `unzip`/`jar`/`javap` |
| `docker-pg-query` | Query PostgreSQL in local Docker containers via `docker exec psql` |
| `image` | Screenshot finder and clipboard paste — platform-aware (macOS, WSL, Linux) |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `bash-safety` | PreToolUse | Forces user confirmation for destructive Bash commands (shell redirects, `find -delete`, git/gradle writes); allows read-only operations silently |
| `format-on-save` | PostToolUse | Auto-formats files after Edit/Write using the appropriate formatter (`shfmt`, `prettier`, `google-java-format`, `ktlint`, `rustfmt`, `ruff`, `markdownlint-cli2`) |

## MCP Servers

| Server | Description |
|--------|-------------|
| `maven-indexer` | Docker Compose service: index Gradle/Maven caches, search classes, CFR decompilation |
| `maven-tools` | Stateless `docker run`: Maven Central versions, CVEs, dependency health |

## Deployment

Run `./deploy` to symlink everything into place. Safe to re-run. (Alternatively, invoke `deploy-py/deploy.py` directly.)

```bash
./deploy                # deploy all tools, hooks, and MCP servers globally
./deploy --on-path      # also symlink scripts to ~/.local/bin/
./deploy --project PATH # deploy skills to <PATH>/.claude/commands/, MCP to .mcp.json
./deploy --dry-run      # show what would be done without making changes
```

### Filtering

```bash
./deploy --include jar-explore,docker-pg-query   # only these tools
./deploy --exclude jar-explore                    # everything except these
```

`--include` and `--exclude` are mutually exclusive and apply across all types (skills, hooks, MCP). Example: deploy a subset globally, then the rest to a project:

```bash
./deploy --include jar-explore,docker-pg-query
./deploy --exclude jar-explore,docker-pg-query --project /path/to/repo
```

### MCP teardown

```bash
./deploy --teardown-mcp maven-tools    # runs setup.sh --teardown, removes config
```

### Other flags

| Flag | Effect |
|------|--------|
| `--skip-permissions` | Skip `settings.json` permission management |

### Deployment config files

Tools, hooks, and MCP servers can be configured via JSON instead of CLI flags. Config is optional.

**Precedence** (lowest → highest):

1. `deploy.json` (repo root) — repo-wide defaults
2. `deploy.local.json` (repo root) — user's global overrides
3. `<type>/<name>/deploy.json` — author defaults
4. `<type>/<name>/deploy.local.json` — user's per-item overrides
5. CLI flags

`*.local.json` files are gitignored.

**Available keys (skills/hooks):**

```json
{
  "enabled": true,
  "scope": "global",
  "on_path": false,
  "permissions": {
    "allow": ["Bash(my-tool)", "Bash(my-tool *)"],
    "deny": []
  },
  "hooks_config": {
    "event": "PreToolUse",
    "matcher": "Bash",
    "command_script": "my-hook.sh"
  }
}
```

**Available keys (MCP servers):**

```json
{
  "enabled": true,
  "mcp": {
    "command": "docker",
    "args": ["run", "--rm", "-i", "some-image:tag"],
    "env": {}
  }
}
```

- **`enabled`** — `false` skips the component entirely
- **`scope`** — `"global"` (default) or `"project"` (requires `--project`)
- **`on_path`** — symlink scripts to `~/.local/bin/`
- **`permissions`** — entries collected and written to `settings.json` (deploy script owns this section)
- **`hooks_config`** — registers hook into `settings.json` `.hooks` (deploy script owns this section). Additional fields: `async` (default `false`), `timeout` (seconds)
- **`mcp`** — server definition written verbatim into `mcpServers.<name>`. Must contain at least `"command"`

## Adding a New Tool

1. Create `skills/<name>/`
2. Add executable scripts in `bin/<script>`
3. Add skill definition(s) as `<name>.md` with YAML frontmatter including a `description:` field
4. (Optional) Add `deploy.json` for deployment config
5. Run `./deploy`

## Adding a New MCP Server

1. Create `mcp/<name>/`
2. Add `deploy.json` with `"mcp"` key containing the server definition
3. (Optional) Add `setup.sh` for install/teardown lifecycle
4. (Optional) Add `docker-compose.yml` if the server needs persistent containers
5. Run `./deploy`

## Testing

```bash
uv run --directory deploy-py pytest deploy-py/tests/   # All deploy.py tests
bash deploy-py/tests/test-bash-safety-hook.sh           # Hook git classifier tests
bash deploy-py/tests/test-bash-safety-gradle.sh         # Hook gradle classifier tests
bash deploy-py/tests/test-format-on-save-hook.sh        # Format-on-save hook tests
```

Deploy tests use `CLAUDE_CONFIG_DIR` pointed at a temp directory — they never touch real config.

## License

MIT
