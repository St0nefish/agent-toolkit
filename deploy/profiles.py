# deploy/profiles.py - Profile loading and drift checking

from pathlib import Path

from deploy.config import load_json


def load_profile(profile_arg: str, repo_root: Path) -> tuple:
    """Load a deployment profile, returning (path_str, data_dict).

    Returns ("", {}) when no profile is active.
    """
    if not profile_arg:
        return "", {}

    profile_file = Path(profile_arg)
    if not profile_file.exists():
        return None, None  # caller handles error
    return str(profile_file), load_json(profile_file)


def check_profile_drift(seen_skills: list, seen_hooks: list,
                        profile_data: dict, seen_mcp: list = None,
                        seen_permissions: list = None) -> list:
    """Compute stale items: in profile but not seen on disk."""
    if not profile_data:
        return []

    if seen_mcp is None:
        seen_mcp = []
    if seen_permissions is None:
        seen_permissions = []

    stale_items = []

    profile_skills = set(profile_data.get("skills", {}).keys())
    profile_hooks = set(profile_data.get("hooks", {}).keys())
    profile_mcp = set(profile_data.get("mcp", {}).keys())
    profile_permissions = set(profile_data.get("permissions", {}).keys())

    for key in sorted(profile_skills):
        if key not in seen_skills:
            stale_items.append(f"{key} (skills)")

    for key in sorted(profile_hooks):
        if key not in seen_hooks:
            stale_items.append(f"{key} (hooks)")

    for key in sorted(profile_mcp):
        if key not in seen_mcp:
            stale_items.append(f"{key} (mcp)")

    for key in sorted(profile_permissions):
        if key not in seen_permissions:
            stale_items.append(f"{key} (permissions)")

    return stale_items
