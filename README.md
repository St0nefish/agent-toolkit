# Claude Dev Skills

Reusable CLI tools and Claude Code skills for development workflows.

## Structure

```
conditionals/          # Reusable deployment gate scripts
  is-wsl.sh           # Exit 0 if running in WSL
  is-macos.sh         # Exit 0 if running on macOS
tools/<name>/          # Individual tools
  bin/<script>        # Executable bash script(s)
  <name>.md           # Claude Code skill definition(s)
  condition.sh        # Optional: deployment condition (symlink to conditionals/)
deploy.sh              # Idempotent deployment script
```

## Deployment

Run `./deploy.sh` to deploy skills. Scripts are invoked via relative paths from skills, so no PATH manipulation needed.

### Global Deployment (default)

```bash
./deploy.sh
```

Deploys all skills to `~/.claude/commands/<name>/` — Claude loads them from there.

### Global + Scripts in PATH

```bash
./deploy.sh --on-path
```

Also symlinks scripts to `~/.local/bin/<script>` — useful if you want to run scripts manually from the terminal.

### Project-Level Deployment

```bash
./deploy.sh --project /path/to/project
```

Deploys skills to `/path/to/project/.claude/commands/<name>/`. Useful for project-specific tools that shouldn't be globally available.

**Note:** `--on-path` is not supported with `--project` (scripts would need to be in every project's PATH, which isn't how PATH works).

## Conditional Deployment

Tools can include a `condition.sh` script. If it exits non-zero, the tool is skipped. Use this for:

- OS-specific tools (e.g., `paste-image-wsl` only deploys in WSL)
- Tools requiring specific commands (e.g., `command -v docker >/dev/null`)

Reusable conditions live in `conditionals/` and can be symlinked:

```bash
tools/<name>/condition.sh -> ../../conditionals/is-wsl.sh
```

## Available Conditionals

| Script | What it checks |
|--------|----------------|
| `is-wsl.sh` | Running under Windows Subsystem for Linux |
| `is-macos.sh` | Running on macOS (Darwin) |

## Tools

| Tool | Description | Condition |
|------|-------------|-----------|
| `jar-explore` | Inspect, search, decompile JAR files | None |
| `docker-pg-query` | Run PostgreSQL diagnostic queries in Docker | None |
| `paste-image-wsl` | Paste images from clipboard (WSL) | `is-wsl.sh` |

## Adding a New Tool

1. Create `tools/<name>/`
2. Add executable scripts in `bin/<script>`
3. Add skill definition(s) as `<name>.md`
4. (Optional) Add `condition.sh` if platform-specific

## License

MIT