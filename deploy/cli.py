# deploy/cli.py - CLI argument parsing and main entry point

import json
import os
import sys
from pathlib import Path

from deploy.config import load_json
from deploy.deploy_skills import deploy_skill
from deploy.deploy_hooks import deploy_hook
from deploy.deploy_mcp import deploy_mcp, teardown_mcp
from deploy.discovery import discover_items, profile_diff
from deploy.linker import cleanup_broken_symlinks
from deploy.permissions import (
    collect_permissions,
    update_settings_permissions,
    update_settings_hooks,
    update_settings_mcp,
    remove_settings_mcp,
)
from deploy.profiles import load_profile, check_profile_drift


def _normalize_list(raw: list[str]) -> list[str]:
    """Flatten a list that may contain comma-separated values.

    Supports both:
      --include foo,bar   -> ['foo,bar'] -> ['foo', 'bar']
      --include foo bar   -> ['foo', 'bar'] -> ['foo', 'bar']
    """
    result = []
    for item in raw:
        for part in item.split(","):
            part = part.strip()
            if part:
                result.append(part)
    return result


def print_usage():
    print("""Usage: ./deploy.py [OPTIONS]

Deploy Claude Code skills, tool scripts, hooks, and MCP servers.

Scripts are always deployed to ~/.claude/tools/<tool-name>/.
Skills (.md files) are deployed to ~/.claude/skills/ (or a project).
Hooks are always deployed to ~/.claude/hooks/<hook-name>/ (global only).
MCP servers are registered in settings.json mcpServers (or .mcp.json).

Options:
  --global               Deploy globally (default, explicit no-op)
  --project PATH         Deploy skills to PATH/.claude/skills/ instead of globally
  --on-path              Also symlink scripts to ~/.local/bin/ (global deploy only)
  --profile PATH         Load a deployment profile (.deploy-profiles/*.json)
  --include TOOL [TOOL]  Only deploy these tools (space or comma-separated)
  --exclude TOOL [TOOL]  Deploy all tools EXCEPT these (space or comma-separated)
  --teardown-mcp NAME [NAME]  Teardown named MCP servers and remove config
  --discover             Output JSON of all items with merged config and exit
  --dry-run              Show what would be done without making any changes
  --skip-permissions     Skip settings.json permission management
  -h, --help             Show this help message

--include and --exclude are mutually exclusive. --global and --project are
mutually exclusive. Tool names match directory names under skills/, hooks/, mcp/.

CLI flags override config file values. Per-tool config is read from JSON
files (see CLAUDE.md for details):
  deploy.json / deploy.local.json          (repo-wide)
  skills/<name>/deploy.json / .local.json  (per-skill)
  .deploy-profiles/*.json                  (deployment profiles)

When --project is used, skills already deployed globally (~/.claude/skills/)
are skipped to avoid conflicts. MCP servers write to .mcp.json instead.

Examples:
  ./deploy.py                                    Deploy all tools
  ./deploy.py --on-path                          Also symlink scripts to ~/.local/bin/
  ./deploy.py --project /path/to/repo            Deploy skills to a specific project
  ./deploy.py --include jar-explore              Deploy only jar-explore
  ./deploy.py --include foo bar                  Space-separated include
  ./deploy.py --include foo,bar                  Comma-separated include
  ./deploy.py --exclude image                    Deploy everything except image
  ./deploy.py --teardown-mcp maven-tools         Teardown an MCP server
  ./deploy.py --discover                         JSON output of all items
  ./deploy.py --discover --profile p.json        JSON with profile diff""")


def parse_args():
    # Manual parsing to support nargs-style --include/--exclude
    # argparse nargs="+" doesn't mix well with our other flags
    args_list = sys.argv[1:]

    opts = {
        "help": False,
        "global_flag": False,
        "project": "",
        "on_path": False,
        "profile": "",
        "include": [],
        "exclude": [],
        "teardown_mcp": [],
        "discover": False,
        "dry_run": False,
        "skip_permissions": False,
    }

    i = 0
    while i < len(args_list):
        arg = args_list[i]
        if arg in ("-h", "--help"):
            opts["help"] = True
            i += 1
        elif arg == "--global":
            opts["global_flag"] = True
            i += 1
        elif arg == "--project":
            i += 1
            if i >= len(args_list):
                print("Error: --project requires a PATH argument", file=sys.stderr)
                sys.exit(1)
            opts["project"] = args_list[i]
            i += 1
        elif arg == "--on-path":
            opts["on_path"] = True
            i += 1
        elif arg == "--profile":
            i += 1
            if i >= len(args_list):
                print("Error: --profile requires a PATH argument", file=sys.stderr)
                sys.exit(1)
            opts["profile"] = args_list[i]
            i += 1
        elif arg == "--no-profile":
            # Accepted for backwards compatibility (now the default)
            i += 1
        elif arg == "--include":
            i += 1
            # Consume all following args until we hit another flag or end
            while i < len(args_list) and not args_list[i].startswith("-"):
                opts["include"].append(args_list[i])
                i += 1
        elif arg == "--exclude":
            i += 1
            while i < len(args_list) and not args_list[i].startswith("-"):
                opts["exclude"].append(args_list[i])
                i += 1
        elif arg == "--teardown-mcp":
            i += 1
            while i < len(args_list) and not args_list[i].startswith("-"):
                opts["teardown_mcp"].append(args_list[i])
                i += 1
            if not opts["teardown_mcp"]:
                print("Error: --teardown-mcp requires at least one NAME argument", file=sys.stderr)
                sys.exit(1)
        elif arg == "--discover":
            opts["discover"] = True
            i += 1
        elif arg == "--dry-run":
            opts["dry_run"] = True
            i += 1
        elif arg == "--skip-permissions":
            opts["skip_permissions"] = True
            i += 1
        else:
            print(f"Error: unrecognized argument: {arg}", file=sys.stderr)
            sys.exit(1)

    # Convert to namespace-like object
    class Args:
        pass
    a = Args()
    for k, v in opts.items():
        setattr(a, k, v)

    # Normalize include/exclude (flatten commas)
    a.include = _normalize_list(a.include)
    a.exclude = _normalize_list(a.exclude)
    a.teardown_mcp = _normalize_list(a.teardown_mcp)

    return a


def main():
    args = parse_args()

    if args.help:
        print_usage()
        sys.exit(1)

    # --- Validate mutually exclusive / conflicting flags ---
    if args.global_flag and args.project:
        print("Error: --global and --project are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    if args.project and args.on_path:
        print("Error: --on-path is not supported with --project", file=sys.stderr)
        sys.exit(1)

    if args.include and args.exclude:
        print("Error: --include and --exclude are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    if args.project and not Path(args.project).is_dir():
        print(f"Error: Project directory does not exist: {args.project}", file=sys.stderr)
        sys.exit(1)

    # --- Resolve paths ---
    repo_root = Path(__file__).resolve().parent.parent
    claude_config_dir = Path(
        os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))
    )

    project_path = Path(args.project).resolve() if args.project else None

    # --- Handle --teardown-mcp ---
    if args.teardown_mcp:
        mcp_base = repo_root / "mcp"
        settings_file = claude_config_dir / "settings.json"

        if args.dry_run:
            print("=== DRY RUN (no changes will be made) ===")
            print("")

        print("=== MCP Teardown ===")
        for name in args.teardown_mcp:
            mcp_dir = mcp_base / name
            if not mcp_dir.is_dir():
                print(f"  Warning: mcp/{name} not found, skipping teardown script")
            else:
                teardown_mcp(mcp_dir, args.dry_run)

        remove_settings_mcp(settings_file, args.teardown_mcp, args.dry_run)
        return

    # --- Profile loading ---
    profile_path, profile_data = load_profile(args.profile, repo_root)

    if profile_path is None:
        # load_profile returns None,None on missing file
        print(f"Error: Profile not found: {args.profile}", file=sys.stderr)
        sys.exit(1)

    # If profile has project_path and CLI --project was not given, use it
    if profile_data and not project_path:
        profile_project = profile_data.get("project_path", "")
        if profile_project:
            profile_project_path = Path(profile_project)
            if not profile_project_path.is_dir():
                print(
                    f"Error: Profile project directory does not exist: {profile_project}",
                    file=sys.stderr,
                )
                sys.exit(1)
            project_path = profile_project_path

    # --- Discover mode ---
    if args.discover:
        result = discover_items(repo_root, profile_data or {})
        if profile_data:
            result["profile_diff"] = profile_diff(result, profile_data)
        print(json.dumps(result, indent=2))
        return

    # --- Base dirs ---
    global_skills_base = claude_config_dir / "skills"
    tools_base = claude_config_dir / "tools"
    hooks_base = claude_config_dir / "hooks"

    # --- Dry-run banner ---
    if args.dry_run:
        print("=== DRY RUN (no changes will be made) ===")
        print("")

    # --- Create base directories ---
    if args.dry_run:
        print(f"> mkdir -p {global_skills_base}")
        print(f"> mkdir -p {tools_base}")
    else:
        global_skills_base.mkdir(parents=True, exist_ok=True)
        tools_base.mkdir(parents=True, exist_ok=True)

    # --- Clean broken symlinks before deploying ---
    cleanup_broken_symlinks(tools_base, "dir", args.dry_run)
    cleanup_broken_symlinks(global_skills_base, "", args.dry_run)

    if project_path:
        project_skills = project_path / ".claude" / "skills"
        if args.dry_run:
            print(f"> mkdir -p {project_skills}")
        else:
            project_skills.mkdir(parents=True, exist_ok=True)
        cleanup_broken_symlinks(project_skills, "", args.dry_run)

    if hooks_base.is_dir():
        cleanup_broken_symlinks(hooks_base, "dir", args.dry_run)

    # --- Always collect repo-root config files for permission management ---
    deployed_configs = []
    for cfg_name in ("deploy.json", "deploy.local.json"):
        p = repo_root / cfg_name
        if p.exists():
            deployed_configs.append(p)

    # --- Deploy skills ---
    skills_dir = repo_root / "skills"
    seen_skills = []
    profile_new_items = []
    hook_configs = []

    if not skills_dir.is_dir():
        print("No skills/ directory found.")
        update_settings_permissions(
            claude_config_dir / "settings.json",
            [], [],
            args.dry_run, args.skip_permissions,
        )
        return

    print("=== Skills ===")
    for skill_dir in sorted(skills_dir.iterdir()):
        if not skill_dir.is_dir():
            continue
        skill_name = skill_dir.name
        seen_skills.append(skill_name)

        deploy_skill(
            skill_dir=skill_dir,
            repo_root=repo_root,
            profile_data=profile_data,
            profile_new_items=profile_new_items,
            include=args.include,
            exclude=args.exclude,
            project_path=project_path,
            cli_on_path=args.on_path,
            global_skills_base=global_skills_base,
            tools_base=tools_base,
            dry_run=args.dry_run,
            deployed_configs=deployed_configs,
            hook_configs=hook_configs,
        )

    # --- Deploy hooks ---
    hooks_dir = repo_root / "hooks"
    seen_hooks = []

    if hooks_dir.is_dir():
        if args.dry_run:
            print(f"> mkdir -p {hooks_base}")
        else:
            hooks_base.mkdir(parents=True, exist_ok=True)

        print("")
        print("=== Hooks ===")
        for hook_dir in sorted(hooks_dir.iterdir()):
            if not hook_dir.is_dir():
                continue
            hook_name = hook_dir.name
            seen_hooks.append(hook_name)

            deploy_hook(
                hook_dir=hook_dir,
                repo_root=repo_root,
                profile_data=profile_data,
                profile_new_items=profile_new_items,
                include=args.include,
                exclude=args.exclude,
                hooks_base=hooks_base,
                dry_run=args.dry_run,
                deployed_configs=deployed_configs,
                hook_configs=hook_configs,
            )

    # --- Deploy MCP servers ---
    mcp_dir_root = repo_root / "mcp"
    seen_mcp = []
    mcp_configs = []

    if mcp_dir_root.is_dir():
        print("")
        print("=== MCP ===")
        for mcp_dir in sorted(mcp_dir_root.iterdir()):
            if not mcp_dir.is_dir():
                continue
            mcp_name = mcp_dir.name
            seen_mcp.append(mcp_name)

            deploy_mcp(
                mcp_dir=mcp_dir,
                repo_root=repo_root,
                profile_data=profile_data,
                profile_new_items=profile_new_items,
                include=args.include,
                exclude=args.exclude,
                project_path=project_path,
                dry_run=args.dry_run,
                deployed_configs=deployed_configs,
                mcp_configs=mcp_configs,
            )

    # --- Manage settings.json permissions ---
    print("")

    seen_paths = set()
    unique_configs = []
    for p in deployed_configs:
        key = str(p)
        if key not in seen_paths:
            seen_paths.add(key)
            unique_configs.append(p)

    allows, denies = collect_permissions(unique_configs)

    settings_file = claude_config_dir / "settings.json"
    if project_path:
        settings_file = project_path / ".claude" / "settings.json"

    update_settings_permissions(settings_file, allows, denies, args.dry_run, args.skip_permissions)

    # --- Manage settings.json hooks (always global) ---
    hooks_settings_file = claude_config_dir / "settings.json"
    update_settings_hooks(
        hooks_settings_file,
        hook_configs,
        hooks_base,
        args.dry_run,
        args.skip_permissions,
    )

    # --- Manage MCP server config ---
    mcp_settings_file = claude_config_dir / "settings.json"
    update_settings_mcp(
        mcp_settings_file,
        mcp_configs,
        project_path,
        args.dry_run,
        args.skip_permissions,
    )

    # --- Summary footer ---
    print("")
    if project_path:
        print(
            f"Deployed to: {project_path}/.claude/skills (project skills) + "
            f"~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
        )
    else:
        print("Deployed to: ~/.claude/skills (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)")

    if mcp_configs:
        names = ", ".join(name for name, _ in mcp_configs)
        print(f"MCP servers registered: {names}")

    if args.on_path:
        print("Scripts also linked to: ~/.local/bin (via --on-path flag)")

    if profile_path:
        print(f"Profile loaded: {profile_path}")

    # --- Check profile drift ---
    if profile_data:
        stale_items = check_profile_drift(seen_skills, seen_hooks, profile_data, seen_mcp)

        if profile_new_items or stale_items:
            print("")
            print("WARNING: Profile drift detected:")
            if profile_new_items:
                print("  New items (not in profile, skipped):")
                for item in profile_new_items:
                    print(f"    - {item}")
            if stale_items:
                print("  Stale items (in profile, no longer on disk):")
                for item in stale_items:
                    print(f"    - {item}")
            print("  Run the deploy wizard to update your profile.")
