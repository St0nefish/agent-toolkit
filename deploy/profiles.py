# deploy/profiles.py - Profile loading and drift checking

from pathlib import Path

from deploy.config import load_json


def load_profile(profile_arg: str, no_profile: bool, repo_root: Path) -> tuple:
    """Load a deployment profile, returning (path_str, data_dict).

    Returns ("", {}) when no profile is active.
    """
    if profile_arg:
        profile_file = Path(profile_arg)
        if not profile_file.exists():
            return None, None  # caller handles error
        return str(profile_file), load_json(profile_file)

    if not no_profile:
        auto_profile = repo_root / ".deploy-profiles" / "global.json"
        if auto_profile.exists():
            return str(auto_profile), load_json(auto_profile)

    return "", {}


def check_profile_drift(seen_skills: list, seen_hooks: list,
                        profile_data: dict) -> list:
    """Compute stale items: in profile but not seen on disk."""
    if not profile_data:
        return []

    stale_items = []

    profile_skills = set(profile_data.get("skills", {}).keys())
    profile_hooks = set(profile_data.get("hooks", {}).keys())

    for key in sorted(profile_skills):
        if key not in seen_skills:
            stale_items.append(f"{key} (skills)")

    for key in sorted(profile_hooks):
        if key not in seen_hooks:
            stale_items.append(f"{key} (hooks)")

    return stale_items
