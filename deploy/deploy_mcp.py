# deploy/deploy_mcp.py - MCP server deployment logic

import subprocess
from pathlib import Path

from deploy.common import pre_deploy_checks


def deploy_mcp(mcp_dir, repo_root, profile_data, profile_new_items,
               include, exclude, project_path, dry_run,
               deployed_configs, mcp_configs):
    """Deploy a single MCP server directory. Returns True if deployed."""
    mcp_dir = Path(mcp_dir)
    mcp_name = mcp_dir.name

    config, skip_reason = pre_deploy_checks(
        mcp_dir, "mcp", repo_root, profile_data,
        profile_new_items, include, exclude,
    )
    if skip_reason:
        print(f"  {skip_reason}")
        return False

    # Validate: config must have an "mcp" key with at least "command"
    mcp_def = config.get("mcp")
    if not isinstance(mcp_def, dict) or "command" not in mcp_def:
        print(f"  Skipped: {mcp_name} (missing or invalid 'mcp' key in deploy.json)")
        return False

    # Run setup.sh if present
    setup_script = mcp_dir / "setup.sh"
    if setup_script.exists() and setup_script.stat().st_mode & 0o111:
        if dry_run:
            print(f"  > Would run: {setup_script}")
        else:
            print(f"  Running: {setup_script}")
            result = subprocess.run(
                [str(setup_script)],
                capture_output=True,
                text=True,
            )
            if result.stdout.strip():
                for line in result.stdout.strip().splitlines():
                    print(f"    {line}")
            if result.returncode != 0:
                print(f"  Warning: {mcp_name} setup.sh failed (exit {result.returncode})")
                if result.stderr.strip():
                    for line in result.stderr.strip().splitlines():
                        print(f"    {line}")
                return False

    # Collect config for MCP settings registration
    mcp_configs.append((mcp_name, mcp_def))

    # Collect deploy.json paths for permission collection
    for cfg_name in ("deploy.json", "deploy.local.json"):
        p = mcp_dir / cfg_name
        if p.exists():
            deployed_configs.append(p)

    print(f"  Deployed: {mcp_name}")
    return True


def teardown_mcp(mcp_dir, dry_run):
    """Run setup.sh --teardown for an MCP server. Returns True on success."""
    mcp_dir = Path(mcp_dir)
    mcp_name = mcp_dir.name

    setup_script = mcp_dir / "setup.sh"
    if not setup_script.exists() or not (setup_script.stat().st_mode & 0o111):
        print(f"  Skipped: {mcp_name} (no setup.sh)")
        return True

    if dry_run:
        print(f"  > Would run: {setup_script} --teardown")
        return True

    print(f"  Running: {setup_script} --teardown")
    result = subprocess.run(
        [str(setup_script), "--teardown"],
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        for line in result.stdout.strip().splitlines():
            print(f"    {line}")
    if result.returncode != 0:
        print(f"  Warning: {mcp_name} teardown failed (exit {result.returncode})")
        if result.stderr.strip():
            for line in result.stderr.strip().splitlines():
                print(f"    {line}")
        return False

    return True
