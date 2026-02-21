# permissions/

This directory contains permission groups — named sets of `allow`/`deny` entries that get merged into `settings.json` when the deploy script runs. Each file represents one logical group of related permissions (e.g., all read-only `git` commands, all `docker` inspection commands).

For full deployment documentation (flags, profiles, `--include`/`--exclude`) see the root `CLAUDE.md`.

---

## How to add a new permission group

1. Create `permissions/<name>.json` with the schema below.
2. Run `./deploy` (or `./deploy --include <name>`) to merge entries into `~/.claude/settings.json`.
3. Optionally create `permissions/<name>.local.json` for personal overrides (gitignored).

That is the entire process. There is no registration step — every `*.json` file in this directory (excluding `*.local.json`) is automatically discovered.

---

## File format and schema

```json
{
  "enabled": true,
  "permissions": {
    "allow": [
      "Bash(my-tool)",
      "Bash(my-tool *)"
    ],
    "deny": []
  }
}
```

Top-level keys:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Set to `false` to skip this group entirely during deployment. |
| `permissions.allow` | string[] | `[]` | Permission entries added to `settings.json` `permissions.allow`. |
| `permissions.deny` | string[] | `[]` | Permission entries added to `settings.json` `permissions.deny`. |

The `permissions` key is the only meaningful payload — no `scope`, `on_path`, or `hooks_config` keys apply to permission groups.

---

## Naming conventions

- File stem becomes the group name: `git.json` → group `git`.
- Use lowercase, hyphen-separated names that describe the toolchain: `bash-read`, `docker`, `github`, `jvm`, `node`, `python`, `rust`, `system`, `web`.
- The name is used for `--include`/`--exclude` filtering and profile management. Keep it short and recognizable.

---

## How allow/deny entries are written

Entries follow Claude Code's permission string syntax:

```
Bash(<command>)          # exact command match
Bash(<command> *)        # command with any arguments
Bash(<command> <args>)   # command with specific fixed prefix
WebFetch(domain:<host>)  # fetch from a specific domain
```

Patterns match the beginning of the Bash invocation. To allow a command both with and without arguments, include both forms:

```
"Bash(git status)", "Bash(git status *)"
```

Only include commands the group logically owns. Keep groups focused — `git.json` covers read-only git introspection, not `git push` or `git commit`.

Existing entries in `settings.json` (including manually added ones) are never removed. The deploy script uses **append-missing** semantics: new entries are merged in; nothing is deleted.

---

## How .local.json overrides work

Create `permissions/<name>.local.json` alongside the tracked file to add personal entries without touching the committed file:

```json
{
  "enabled": true,
  "permissions": {
    "allow": [
      "Bash(my-internal-tool)",
      "Bash(my-internal-tool *)"
    ]
  }
}
```

`*.local.json` files are gitignored. They are merged on top of the tracked file — both files' `allow` and `deny` entries are collected together. To disable a group locally without editing the tracked file:

```json
{ "enabled": false }
```

---

## Minimal example: creating a new permission group

```bash
cat > permissions/terraform.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(terraform --version)",
      "Bash(terraform fmt -check)", "Bash(terraform fmt -check *)",
      "Bash(terraform graph)", "Bash(terraform graph *)",
      "Bash(terraform output)", "Bash(terraform output *)",
      "Bash(terraform plan)", "Bash(terraform plan *)",
      "Bash(terraform show)", "Bash(terraform show *)",
      "Bash(terraform validate)", "Bash(terraform validate *)",
      "Bash(terraform workspace list)", "Bash(terraform workspace list *)"
    ]
  }
}
EOF
```

Then deploy:

```bash
./deploy --include terraform
```

To verify without making changes:

```bash
./deploy --include terraform --dry-run
```

---

## How permissions get deployed to settings.json

During `./deploy`:

1. Discovers every `permissions/*.json` file (skipping `*.local.json`).
2. Applies the config merge layers (repo defaults → local overrides → per-file → per-file local) to resolve `enabled`.
3. Enabled groups have their `permissions.allow` and `permissions.deny` entries collected into a flat set — duplicates are dropped.
4. Permissions from skill/hook `deploy.json` files are also collected at this stage.
5. The combined set is sorted into visual groups (bash-read, system, git, docker, python, node, jvm, rust, web, then other) and merged into `~/.claude/settings.json` using append-missing semantics.

Deployment is idempotent — running `./deploy` multiple times produces the same result.
