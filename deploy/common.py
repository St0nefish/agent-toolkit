# deploy/common.py - Shared pre-deployment guards

from pathlib import Path

from deploy.config import resolve_config, apply_profile_overrides
from deploy.filters import is_filtered_out


def pre_deploy_checks(item_dir, item_type, repo_root, profile_data,
                      profile_new_items, include, exclude):
    """Run shared pre-deployment gates.

    Returns (config, skip_reason) where skip_reason is None if deployment
    should proceed, or a string message if it should be skipped.
    """
    item_dir = Path(item_dir)
    item_name = item_dir.name

    if is_filtered_out(item_name, include, exclude):
        return None, f"Skipped: {item_name} (filtered out)"

    config = resolve_config(item_dir, repo_root)

    if profile_data and item_name not in profile_data.get(item_type, {}):
        profile_new_items.append(f"{item_name} ({item_type})")

    config = apply_profile_overrides(config, profile_data, item_type, item_name)

    if not config.get("enabled", True):
        return None, f"Skipped: {item_name} (disabled by config)"

    return config, None
