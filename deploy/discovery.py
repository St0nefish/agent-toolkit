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
        "permissions": discover_permissions(repo_root, profile_data),
    }


def discover_permissions(repo_root: Path, profile_data: dict) -> list[dict]:
    """Discover permission groups in permissions/."""
    import functools
    from deploy.config import DEFAULTS, load_json

    perm_dir = repo_root / "permissions"
    if not perm_dir.is_dir():
        return []

    items = []
    for base_file in sorted(perm_dir.glob("*.json")):
        if base_file.name.endswith(".local.json"):
            continue
        name = base_file.stem
        local_file = base_file.parent / f"{name}.local.json"

        layers = [
            DEFAULTS,
            load_json(repo_root / "deploy.json"),
            load_json(repo_root / "deploy.local.json"),
            load_json(base_file),
            load_json(local_file),
        ]
        config = functools.reduce(lambda a, b: {**a, **b}, layers)
        config = apply_profile_overrides(config, profile_data, "permissions", name)

        items.append({
            "name": name,
            "enabled": config.get("enabled", True),
            "scope": config.get("scope", "global"),
        })

    return items


def profile_diff(discover_data: dict, profile_data: dict) -> dict:
    """Compare discover output with a deployment profile.

    Returns {"added": {...}, "removed": {...}} where each has
    skills, hooks, mcp arrays of item names.
    """
    types = ["skills", "hooks", "mcp", "permissions"]

    added = {}
    removed = {}

    for t in types:
        on_disk = [item["name"] for item in discover_data.get(t) or [] if "name" in item]
        in_profile = list((profile_data.get(t) or {}).keys())
        added[t] = [name for name in on_disk if name not in in_profile]
        removed[t] = [name for name in in_profile if name not in on_disk]

    return {"added": added, "removed": removed}
