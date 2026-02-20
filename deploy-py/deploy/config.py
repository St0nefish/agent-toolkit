# deploy/config.py - Config loading, merging, profile overrides

import functools
import json
from pathlib import Path

DEFAULTS = {"enabled": True, "scope": "global", "on_path": False}


def load_json(path) -> dict:
    """Load a JSON file, returning {} on missing or parse error."""
    try:
        return json.loads(Path(path).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def resolve_config(item_dir: Path, repo_root: Path) -> dict:
    """Resolve deployment config for a tool/hook by merging 5 config layers.

    Layers (lowest -> highest priority):
      1. Hardcoded defaults
      2. Repo-root deploy.json
      3. Repo-root deploy.local.json
      4. Item-level deploy.json
      5. Item-level deploy.local.json

    Uses shallow merge: right-hand value wins for each key.
    """
    layers = [
        DEFAULTS,
        load_json(repo_root / "deploy.json"),
        load_json(repo_root / "deploy.local.json"),
        load_json(item_dir / "deploy.json"),
        load_json(item_dir / "deploy.local.json"),
    ]
    return functools.reduce(lambda a, b: {**a, **b}, layers)


def apply_profile_overrides(config: dict, profile_data: dict,
                            item_type: str, item_name: str) -> dict:
    """Apply profile overrides onto a resolved config dict.

    When a profile is loaded it is AUTHORITATIVE:
    - Items listed in the profile: merge their enabled/on_path values only
    - Items NOT in the profile: disabled (set enabled=False)

    Only 'enabled' and 'on_path' keys are extracted from profile per-item;
    all other keys (scope, permissions, etc.) are silently ignored.
    """
    if not profile_data:
        return config

    items = profile_data.get(item_type, {})
    if item_name not in items:
        return {**config, "enabled": False}

    item_overrides = items[item_name]
    # Whitelist: only enabled and on_path
    allowed = {k: v for k, v in item_overrides.items()
               if k in ("enabled", "on_path") and v is not None}
    return {**config, **allowed}
