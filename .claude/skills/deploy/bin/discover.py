#!/usr/bin/env python3
"""Discovers deployable items in a claude-toolkit repo.

Validates the repo root (deploy.py must exist), detects
profiles, and outputs full merged config for every item.

Output JSON:
{
  "repo_root": "/abs/path",
  "profiles": ["global.json", ...],
  "skills": [...],
  "hooks": [...],
  "mcp": [...]
}

Each item: { "name": "...", "enabled": true, "scope": "global", "on_path": false }

Replicates the full 5-layer resolve_config merge chain from deploy.py,
plus an optional 6th layer from a deployment profile (--profile).
"""

import json
import sys
from pathlib import Path


def main():
    repo_root = None
    profile_path = None

    # Parse args: discover [--profile PATH] [REPO_ROOT]
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--profile":
            profile_path = args[i + 1]
            i += 2
        else:
            repo_root = args[i]
            i += 1

    repo_root = Path(repo_root or ".").resolve()

    # Validate repo root
    if not (repo_root / "deploy.py").exists():
        print(json.dumps({"error": f"deploy.py not found in repo root: {repo_root}"}),
              file=sys.stderr)
        sys.exit(1)

    # Import helpers from deploy.py
    sys.path.insert(0, str(repo_root))
    import deploy  # noqa: E402
    load_json = deploy.load_json
    resolve_config = deploy.resolve_config
    apply_profile_overrides = deploy.apply_profile_overrides

    # Detect profiles
    profiles_dir = repo_root / ".deploy-profiles"
    profiles = sorted(p.name for p in profiles_dir.glob("*.json")) if profiles_dir.is_dir() else []

    # Load profile data if given
    profile_data = load_json(profile_path) if profile_path else {}

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

    result = {
        "repo_root": str(repo_root),
        "profiles": profiles,
        "skills": discover_category("skills"),
        "hooks": discover_category("hooks"),
        "mcp": discover_category("mcp"),
    }

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
