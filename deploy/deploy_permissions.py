# deploy/deploy_permissions.py - Permission group deployment logic

import functools
from pathlib import Path

from deploy.config import DEFAULTS, apply_profile_overrides, load_json
from deploy.filters import is_filtered_out


def deploy_permission_groups(permissions_dir, repo_root, profile_data,
                             profile_new_items, include, exclude,
                             dry_run, deployed_configs):
    """Process all permission groups in permissions/. Returns list of seen names."""
    seen = []
    for base_file in sorted(permissions_dir.glob("*.json")):
        if base_file.name.endswith(".local.json"):
            continue
        group_name = base_file.stem  # "git" from "git.json"
        seen.append(group_name)

        if is_filtered_out(group_name, include, exclude):
            print(f"  Skipped: {group_name} (filtered out)")
            continue

        config = _resolve_permission_config(base_file, repo_root)
        config = apply_profile_overrides(config, profile_data, "permissions", group_name)

        if profile_data and group_name not in profile_data.get("permissions", {}):
            profile_new_items.append(f"{group_name} (permissions)")

        if not config.get("enabled", True):
            print(f"  Skipped: {group_name} (disabled)")
            continue

        deployed_configs.append(base_file)
        local_file = base_file.parent / f"{group_name}.local.json"
        if local_file.exists():
            deployed_configs.append(local_file)

        if dry_run:
            print(f"  > Include: {group_name}")
        else:
            print(f"  Included: {group_name}")

    return seen


def _resolve_permission_config(base_file, repo_root):
    """Resolve config for a permission group file using 5-layer merge.

    Layers (lowest -> highest priority):
      1. Hardcoded defaults (enabled, scope)
      2. Repo-root deploy.json
      3. Repo-root deploy.local.json
      4. <name>.json (the base file itself)
      5. <name>.local.json (the local override)

    Only enabled and scope keys are meaningful for permission groups.
    """
    group_name = base_file.stem
    local_file = base_file.parent / f"{group_name}.local.json"

    layers = [
        DEFAULTS,
        load_json(repo_root / "deploy.json"),
        load_json(repo_root / "deploy.local.json"),
        load_json(base_file),
        load_json(local_file),
    ]
    return functools.reduce(lambda a, b: {**a, **b}, layers)
