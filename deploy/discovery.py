# deploy/discovery.py - Item discovery and profile diffing

import json
from pathlib import Path

from deploy.config import resolve_config, apply_profile_overrides


def discover_items(repo_root: Path, profile_data: dict = None) -> dict:
    """Discover all deployable items in the repo.

    Returns a dict with repo_root, profiles, skills, hooks, mcp arrays.
    Each item: {"name": ..., "enabled": ..., "scope": ..., "on_path": ...}
    """
    if profile_data is None:
        profile_data = {}

    profiles_dir = repo_root / ".deploy-profiles"
    profiles = sorted(p.name for p in profiles_dir.glob("*.json")) if profiles_dir.is_dir() else []

    def discover_category(category: str) -> list[dict]:
        cat_dir = repo_root / category
        if not cat_dir.is_dir():
            return []

        items = []
        for item_dir in sorted(cat_dir.iterdir()):
            if not item_dir.is_dir():
                continue
            name = item_dir.name

            config = resolve_config(item_dir, repo_root)
            config = apply_profile_overrides(config, profile_data, category, name)

            items.append({
                "name": name,
                "enabled": config.get("enabled", True),
                "scope": config.get("scope", "global"),
                "on_path": config.get("on_path", False),
            })

        return items

    return {
        "repo_root": str(repo_root),
        "profiles": profiles,
        "skills": discover_category("skills"),
        "hooks": discover_category("hooks"),
        "mcp": discover_category("mcp"),
    }


def profile_diff(discover_data: dict, profile_data: dict) -> dict:
    """Compare discover output with a deployment profile.

    Returns {"added": {...}, "removed": {...}} where each has
    skills, hooks, mcp arrays of item names.
    """
    types = ["skills", "hooks", "mcp"]

    added = {}
    removed = {}

    for t in types:
        on_disk = [item["name"] for item in discover_data.get(t) or [] if "name" in item]
        in_profile = list((profile_data.get(t) or {}).keys())
        added[t] = [name for name in on_disk if name not in in_profile]
        removed[t] = [name for name in in_profile if name not in on_disk]

    return {"added": added, "removed": removed}
