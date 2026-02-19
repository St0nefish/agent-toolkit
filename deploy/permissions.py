# deploy/permissions.py - Settings.json permission and hook management

import json
import os
from pathlib import Path

from deploy.config import load_json


def collect_permissions(config_files: list) -> tuple:
    """Gather all permission entries from a list of config file paths.

    Returns (allows, denies) as sorted, deduplicated lists of strings.
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

    return sorted(all_allows), sorted(all_denies)


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

    merged_allows = sorted(set(existing_allows) | set(allows))
    merged_denies = sorted(set(existing_denies) | set(denies))

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


def _atomic_write_json(path: Path, data: dict):
    """Write JSON to path atomically via a tmp file + os.replace()."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(str(tmp), str(path))
