# deploy/permissions.py - Settings.json permission and hook management

import json
import os
from pathlib import Path

from deploy.config import load_json


def collect_permissions(config_files: list) -> tuple:
    """Gather all permission entries from a list of config file paths.

    Returns (allows, denies) as sorted, deduplicated lists of strings.
    Sorting groups related entries together by category.
    """
    all_allows = set()
    all_denies = set()

    for path in config_files:
        data = load_json(path)
        perms = data.get("permissions", {})
        for entry in perms.get("allow", []):
            if entry:
                all_allows.add(entry)
        for entry in perms.get("deny", []):
            if entry:
                all_denies.add(entry)

    return sorted(all_allows, key=_permission_sort_key), sorted(all_denies, key=_permission_sort_key)


def update_settings_permissions(settings_path: Path, allows: list, denies: list,
                                dry_run: bool, skip_permissions: bool):
    """Merge permission entries into settings.json using append-missing semantics.

    Existing entries (including manually added ones) are preserved.
    New entries are appended. All entries are deduplicated and sorted.
    """
    if skip_permissions:
        print("Skipped: permissions management (--skip-permissions)")
        return

    if dry_run:
        print(f"> Would update {settings_path} permissions ({len(allows)} allow entries)")
        return

    existing = load_json(settings_path)

    existing_allows = existing.get("permissions", {}).get("allow", [])
    existing_denies = existing.get("permissions", {}).get("deny", [])

    merged_allows = sorted(set(existing_allows) | set(allows), key=_permission_sort_key)
    merged_denies = sorted(set(existing_denies) | set(denies), key=_permission_sort_key)

    if "permissions" not in existing:
        existing["permissions"] = {}
    existing["permissions"]["allow"] = merged_allows
    existing["permissions"]["deny"] = merged_denies

    _atomic_write_json(settings_path, existing)

    count = len(merged_allows)
    print(f"Updated: {settings_path} permissions ({count} allow entries)")


def update_settings_hooks(settings_path: Path, hook_configs: list,
                          hooks_base: Path, dry_run: bool,
                          skip_permissions: bool):
    """Build the hooks JSON object from collected hook configs and merge into settings.json.

    Uses append-missing semantics: existing event+matcher pairs are preserved;
    only new ones are added. Manually added hooks survive re-deployment.

    hook_configs: list of (hook_name, config_path) tuples
    """
    if skip_permissions:
        print("Skipped: hooks management (--skip-permissions)")
        return

    if not hook_configs:
        return

    new_hooks = {}
    for hook_name, config_path in hook_configs:
        data = load_json(config_path)
        hc = data.get("hooks_config", {})
        if not hc:
            continue

        event = hc.get("event")
        matcher = hc.get("matcher")
        command_script = hc.get("command_script")
        async_flag = hc.get("async", False)
        timeout_val = hc.get("timeout")

        if not event or not matcher or not command_script:
            continue

        command_path = str(hooks_base / hook_name / command_script)

        hook_entry = {"type": "command", "command": command_path}
        if async_flag:
            hook_entry["async"] = True
        if timeout_val is not None:
            hook_entry["timeout"] = timeout_val

        matcher_group = {"matcher": matcher, "hooks": [hook_entry]}

        if event not in new_hooks:
            new_hooks[event] = []
        new_hooks[event].append(matcher_group)

    if dry_run:
        event_count = len(new_hooks)
        print(f"> Would update {settings_path} hooks ({event_count} events)")
        return

    existing = load_json(settings_path)
    existing_hooks = existing.get("hooks", {})

    for event, groups in new_hooks.items():
        if event not in existing_hooks:
            existing_hooks[event] = []
        for group in groups:
            already_present = any(
                g.get("matcher") == group["matcher"]
                for g in existing_hooks[event]
            )
            if not already_present:
                existing_hooks[event].append(group)

    existing["hooks"] = existing_hooks
    _atomic_write_json(settings_path, existing)

    event_count = len(existing_hooks)
    print(f"Updated: {settings_path} hooks ({event_count} events)")


def update_settings_mcp(settings_path: Path, mcp_configs: list,
                        project_path, dry_run: bool, skip_permissions: bool):
    """Merge MCP server definitions into settings using append-missing semantics.

    mcp_configs: list of (server_name, server_def) tuples.
    When project_path is set, writes to <project>/.mcp.json instead.
    Existing servers (including manually configured ones) are preserved.
    """
    if skip_permissions:
        print("Skipped: MCP server management (--skip-permissions)")
        return

    if not mcp_configs:
        return

    if project_path:
        target_path = Path(project_path) / ".mcp.json"
    else:
        target_path = settings_path

    if dry_run:
        names = ", ".join(name for name, _ in mcp_configs)
        print(f"> Would update {target_path} mcpServers ({names})")
        return

    existing = load_json(target_path)
    existing_servers = existing.get("mcpServers", {})

    for name, server_def in mcp_configs:
        if name not in existing_servers:
            existing_servers[name] = server_def

    existing["mcpServers"] = existing_servers
    _atomic_write_json(target_path, existing)

    count = len(existing_servers)
    print(f"Updated: {target_path} mcpServers ({count} servers)")


def remove_settings_mcp(settings_path: Path, server_names: list,
                         dry_run: bool):
    """Remove named MCP servers from settings.

    Operates on settings_path (global settings.json).
    """
    if not server_names:
        return

    if dry_run:
        names = ", ".join(server_names)
        print(f"> Would remove from {settings_path} mcpServers: {names}")
        return

    existing = load_json(settings_path)
    servers = existing.get("mcpServers", {})

    removed = []
    for name in server_names:
        if name in servers:
            del servers[name]
            removed.append(name)

    if removed:
        existing["mcpServers"] = servers
        _atomic_write_json(settings_path, existing)
        print(f"Removed from {settings_path} mcpServers: {', '.join(removed)}")
    else:
        print(f"No matching MCP servers found in {settings_path}")


_PERMISSION_GROUPS = [
    ("Bash(cat",      "01-bash-read"),
    ("Bash(column",   "01-bash-read"),
    ("Bash(cut",      "01-bash-read"),
    ("Bash(diff",     "01-bash-read"),
    ("Bash(file",     "01-bash-read"),
    ("Bash(find",     "01-bash-read"),
    ("Bash(grep",     "01-bash-read"),
    ("Bash(head",     "01-bash-read"),
    ("Bash(jq",       "01-bash-read"),
    ("Bash(ls",       "01-bash-read"),
    ("Bash(md5sum",   "01-bash-read"),
    ("Bash(readlink", "01-bash-read"),
    ("Bash(realpath", "01-bash-read"),
    ("Bash(rg",       "01-bash-read"),
    ("Bash(sha256sum","01-bash-read"),
    ("Bash(sort",     "01-bash-read"),
    ("Bash(stat",     "01-bash-read"),
    ("Bash(tail",     "01-bash-read"),
    ("Bash(tar",      "01-bash-read"),
    ("Bash(test",     "01-bash-read"),
    ("Bash(tr",       "01-bash-read"),
    ("Bash(tree",     "01-bash-read"),
    ("Bash(uniq",     "01-bash-read"),
    ("Bash(unzip",    "01-bash-read"),
    ("Bash(wc",       "01-bash-read"),
    ("Bash(which",    "01-bash-read"),
    ("Bash(zip",      "01-bash-read"),
    ("Bash(date",     "02-system"),
    ("Bash(df",       "02-system"),
    ("Bash(du",       "02-system"),
    ("Bash(hostname", "02-system"),
    ("Bash(id",       "02-system"),
    ("Bash(lsof",     "02-system"),
    ("Bash(netstat",  "02-system"),
    ("Bash(printenv", "02-system"),
    ("Bash(ps",       "02-system"),
    ("Bash(pwd",      "02-system"),
    ("Bash(ss",       "02-system"),
    ("Bash(top",      "02-system"),
    ("Bash(uname",    "02-system"),
    ("Bash(uptime",   "02-system"),
    ("Bash(whoami",   "02-system"),
    ("Bash(git ",     "03-git"),
    ("Bash(docker",   "04-docker"),
    ("Bash(gh ",      "05-github"),
    ("Bash(python",   "06-python"),
    ("Bash(python3",  "06-python"),
    ("Bash(pip",      "06-python"),
    ("Bash(pip3",     "06-python"),
    ("Bash(uv ",      "06-python"),
    ("Bash(poetry",   "06-python"),
    ("Bash(pyenv",    "06-python"),
    ("Bash(pipenv",   "06-python"),
    ("Bash(node",     "07-node"),
    ("Bash(npm",      "07-node"),
    ("Bash(npx",      "07-node"),
    ("Bash(yarn",     "07-node"),
    ("Bash(pnpm",     "07-node"),
    ("Bash(nvm",      "07-node"),
    ("Bash(deno",     "07-node"),
    ("Bash(java",     "08-jvm"),
    ("Bash(javac",    "08-jvm"),
    ("Bash(javap",    "08-jvm"),
    ("Bash(jar ",     "08-jvm"),
    ("Bash(gradle",   "08-jvm"),
    ("Bash(./gradlew","08-jvm"),
    ("Bash(mvn",      "08-jvm"),
    ("Bash(kotlin",   "08-jvm"),
    ("Bash(rustc",    "09-rust"),
    ("Bash(rustup",   "09-rust"),
    ("Bash(cargo",    "09-rust"),
    ("Bash(~/.claude/tools/", "10-tools"),
    ("Bash(command",  "10-tools"),
    ("WebFetch",      "11-web"),
]


def _permission_sort_key(entry: str) -> tuple:
    """Sort permissions into visual groups, then alphabetically within each group."""
    for prefix, group in _PERMISSION_GROUPS:
        if entry.startswith(prefix):
            return (group, entry)
    return ("99-other", entry)


def _atomic_write_json(path: Path, data: dict):
    """Write JSON to path atomically via a tmp file + os.replace()."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(str(tmp), str(path))
