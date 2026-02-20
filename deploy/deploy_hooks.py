# deploy/deploy_hooks.py - Hook deployment logic

from pathlib import Path

from deploy.common import collect_deploy_configs, pre_deploy_checks
from deploy.config import load_json
from deploy.linker import ensure_link


def deploy_hook(
        hook_dir,
        repo_root,
        profile_data,
        profile_new_items,
        include,
        exclude,
        hooks_base,
        dry_run,
        deployed_configs,
        hook_configs,
):
    """Deploy a single hook directory. Returns True if deployed."""
    hook_dir = Path(hook_dir)
    hook_name = hook_dir.name

    config, skip_reason = pre_deploy_checks(
        hook_dir, "hooks", repo_root, profile_data,
        profile_new_items, include, exclude,
    )
    if skip_reason:
        # Prefix with "hook" for consistent messaging
        print(f"  {skip_reason.replace('Skipped: ', 'Skipped: hook ')}")
        return False

    ensure_link(
        hooks_base / hook_name,
        hook_dir,
        f"~/.claude/hooks/{hook_name}",
        dry_run,
        for_dir=True,
    )

    collect_deploy_configs(hook_dir, deployed_configs)

    hook_deploy_json = hook_dir / "deploy.json"
    if hook_deploy_json.exists():
        data = load_json(hook_deploy_json)
        if "hooks_config" in data:
            hook_configs.append((hook_name, hook_deploy_json))

    print(f"  Deployed: hook {hook_name}")
    return True
