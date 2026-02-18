# Claude Toolkit

Reusable CLI tools, hooks, and MCP servers for Claude Code development workflows. Each component is self-contained and deployed via a single idempotent script.

## Structure

```
conditionals/                  ← reusable deployment gate scripts
  is-wsl.sh                   ← exit 0 if WSL, exit 1 otherwise
  is-macos.sh                 ← exit 0 if macOS, exit 1 otherwise
skills/
  <name>/                     ← one folder per skill
    bin/<script>              ← executable(s)
    <name>.md                 ← skill definition(s)
    condition.sh              ← optional: deployment gate
    deploy.json               ← optional: deployment config (tracked)
    deploy.local.json         ← optional: user overrides (gitignored)
hooks/
  <name>/                     ← one folder per hook
    <script>.sh              ← hook script(s)
    condition.sh              ← optional: deployment gate
    deploy.json               ← optional: deployment config (tracked)
    deploy.local.json         ← optional: user overrides (gitignored)
mcp-servers/
  <name>/                     ← MCP server stacks (e.g., Docker Compose)
tests/                         ← test scripts (plain bash)
deploy.sh                     ← idempotent deployment script
deploy.json                   ← optional: repo-wide deployment config (tracked)
deploy.local.json             ← optional: user overrides (gitignored)
```

After deployment:

```
~/.claude/tools/<name>/        ← symlink to skills/<name>/
~/.claude/commands/<x>.md      ← symlink to individual skill .md files
~/.claude/hooks/<name>/        ← symlink to hooks/<name>/
~/.local/bin/<script>          ← optional (--on-path), for direct human use
```

## Tools

| Tool | Description | Condition |
|------|-------------|-----------|
| `jar-explore` | Inspect, search, and read files inside JARs — replaces raw `unzip`/`jar`/`javap` | None |
| `docker-pg-query` | Query PostgreSQL in local Docker containers via `docker exec psql` | None |
| `image` | Screenshot finder and clipboard paste — platform-aware (macOS, WSL, Linux) | None |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `bash-safety` | PreToolUse | Forces user confirmation for destructive Bash commands (shell redirects, `find -delete`, git/gradle writes); allows read-only operations silently |
| `format-on-save` | PostToolUse | Auto-formats files after Edit/Write using the appropriate formatter (`shfmt`, `prettier`, `google-java-format`, `ktlint`, `rustfmt`, `ruff`, `markdownlint-cli2`) |

## MCP Servers

| Server | Description |
|--------|-------------|
| `java-dev` | Docker Compose stack: `maven-indexer-mcp` (search/decompile classes in local Gradle/Maven caches) + `maven-tools-mcp` (Maven Central versions, CVEs, docs) |

## Deployment

Run `./deploy.sh` to symlink everything into place. Safe to re-run.

```bash
./deploy.sh                # deploy all tools and hooks globally
./deploy.sh --on-path      # also symlink scripts to ~/.local/bin/
./deploy.sh --project PATH # deploy skills to <PATH>/.claude/commands/
./deploy.sh --dry-run      # show what would be done without making changes
```

### Filtering

```bash
./deploy.sh --include jar-explore,docker-pg-query   # only these tools
./deploy.sh --exclude jar-explore                    # everything except these
```

`--include` and `--exclude` are mutually exclusive. Example: deploy a subset globally, then the rest to a project:

```bash
./deploy.sh --include jar-explore,docker-pg-query
./deploy.sh --exclude jar-explore,docker-pg-query --project /path/to/repo
```

### Other flags

| Flag | Effect |
|------|--------|
| `--skip-permissions` | Skip `settings.json` permission management |

### Conditional deployment

If `skills/<name>/condition.sh` (or `hooks/<name>/condition.sh`) exists and exits non-zero, that component is skipped. Reusable conditions live in `conditionals/` and can be symlinked:

```bash
skills/<name>/condition.sh -> ../../conditionals/is-wsl.sh
```

| Script | Checks |
|--------|--------|
| `is-wsl.sh` | Running under WSL |
| `is-macos.sh` | Running on macOS |

### Deployment config files

Tools and hooks can be configured via JSON instead of CLI flags. Config is optional.

**Precedence** (lowest → highest):

1. `deploy.json` (repo root) — repo-wide defaults
2. `deploy.local.json` (repo root) — user's global overrides
3. `skills/<name>/deploy.json` — skill author defaults
4. `skills/<name>/deploy.local.json` — user's per-skill overrides
5. CLI flags

`*.local.json` files are gitignored.

**Available keys:**

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

- **`enabled`** — `false` skips the component entirely
- **`scope`** — `"global"` (default) or `"project"` (requires `--project`)
- **`on_path`** — symlink scripts to `~/.local/bin/`
- **`permissions`** — entries collected and written to `settings.json` (deploy script owns this section)
- **`hooks_config`** — registers hook into `settings.json` `.hooks` (deploy script owns this section). Additional fields: `async` (default `false`), `timeout` (seconds)

## Adding a New Tool

1. Create `skills/<name>/`
2. Add executable scripts in `bin/<script>`
3. Add skill definition(s) as `<name>.md` with YAML frontmatter including a `description:` field
4. (Optional) Add `condition.sh` if platform-specific
5. (Optional) Add `deploy.json` for deployment config
6. Run `./deploy.sh`

## Testing

```bash
bash tests/test-bash-safety-hook.sh       # Hook git classifier tests
bash tests/test-bash-safety-gradle.sh     # Hook gradle classifier tests
bash tests/test-deploy-permissions.sh     # Deploy permission management tests
bash tests/test-deploy-hooks.sh           # Deploy hook registration tests
bash tests/test-format-on-save-hook.sh    # Format-on-save hook tests
```

Deploy tests use `CLAUDE_CONFIG_DIR` pointed at a temp directory — they never touch real config.

## License

MIT
