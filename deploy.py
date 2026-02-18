#!/usr/bin/env python3
# deploy.py - Deploy Claude Code skills, tool scripts, and hooks
# Idempotent: safe to re-run (overwrites existing symlinks)
#
# Scripts deploy to:  ~/.claude/tools/<tool-name>/  (always)
# Skills deploy to:   ~/.claude/commands/ or <project>/.claude/commands/
# Hooks deploy to:    ~/.claude/hooks/<hook-name>/  (always global)
# --on-path also:     ~/.local/bin/  (symlinks to individual scripts)

import argparse
import functools
import json
import os
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULTS = {"enabled": True, "scope": "global", "on_path": False}

# ---------------------------------------------------------------------------
# JSON / config helpers
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Condition & filtering
# ---------------------------------------------------------------------------

def check_condition(item_dir: Path) -> bool:
    """Run condition.sh if present. Returns True if condition is met (deploy)."""
    cond = item_dir / "condition.sh"
    if not cond.exists():
        return True
    result = subprocess.run(
        [str(cond)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def is_filtered_out(name: str, include: str, exclude: str) -> bool:
    """Return True if the item should be skipped by --include/--exclude."""
    if include:
        include_list = [s.strip() for s in include.split(",")]
        return name not in include_list
    if exclude:
        exclude_list = [s.strip() for s in exclude.split(",")]
        return name in exclude_list
    return False


# ---------------------------------------------------------------------------
# Symlink operations
# ---------------------------------------------------------------------------

def ensure_link(link: Path, target: Path, label: str, dry_run: bool,
                for_dir: bool = False) -> str:
    """Create or verify a symlink from link -> target.

    - In dry-run mode: prints the command that would run
    - If symlink already points to target: prints "OK: <label>"
    - Otherwise: creates/overwrites the symlink and prints "Linked: <label>"

    Returns "OK" or "Linked".
    """
    if not dry_run:
        try:
            existing = link.readlink()
            if existing == target:
                print(f"OK: {label}")
                return "OK"
        except (OSError, ValueError):
            pass

    if dry_run:
        flag = "-sfn" if for_dir else "-sf"
        print(f"> ln {flag} {target} {link}")
    else:
        # Unlink any existing symlink/file, then create new one
        try:
            link.unlink(missing_ok=True)
        except OSError:
            pass
        link.symlink_to(target)

    print(f"Linked: {label}")
    return "Linked"


def cleanup_broken_symlinks(directory: Path, filter_type: str, dry_run: bool):
    """Remove broken symlinks in a directory.

    filter_type: '' (all), 'dir' (only dir symlinks), 'file' (only file symlinks)

    For the commands directory (filter_type != 'dir'), also cleans subdirectories
    that contain only broken symlinks.
    """
    if not directory.is_dir():
        return

    # Clean top-level broken symlinks
    for link in directory.iterdir():
        if not link.is_symlink():
            continue
        if link.exists():
            continue
        # It's a broken symlink
        if dry_run:
            print(f"> Would remove broken symlink: {link}")
        else:
            link.unlink(missing_ok=True)
            print(f"Cleaned: broken symlink {link} (target gone)")

    # For commands dirs (not filtering for dirs): clean empty subdirs
    if filter_type != "dir":
        for subdir in directory.iterdir():
            if not subdir.is_dir():
                continue
            # Skip if subdir is itself a symlink (tool dirs)
            if subdir.is_symlink():
                continue
            # Check if all symlinks inside are broken (or there are none)
            has_valid = False
            entries = list(subdir.iterdir())
            for entry in entries:
                if entry.is_symlink() and entry.exists():
                    has_valid = True
                    break
            if not has_valid:
                # Remove broken links then the dir
                for entry in entries:
                    if entry.is_symlink():
                        if dry_run:
                            print(f"> Would remove broken symlink: {entry}")
                        else:
                            entry.unlink(missing_ok=True)
                            print(f"Cleaned: broken symlink {entry} (target gone)")
                if dry_run:
                    print(f"> Would remove empty commands subdirectory: {subdir}")
                else:
                    try:
                        subdir.rmdir()
                        print(f"Cleaned: empty commands subdirectory {subdir}")
                    except OSError:
                        pass


# ---------------------------------------------------------------------------
# Settings management
# ---------------------------------------------------------------------------

def collect_permissions(config_files: list) -> tuple:
    """Gather all permission entries from a list of config file paths.

    Returns (allows, denies) as sorted, deduplicated lists of strings.
    """
    all_allows = set()
    all_denies = set()

    for path in config_files:
        data = load_json(path)
        perms = data.get("permissions", {})
        for entry in perms.get("allow", []):
            if entry:
                all_allows.add(entry)
        for entry in perms.get("deny", []):
            if entry:
                all_denies.add(entry)

    return sorted(all_allows), sorted(all_denies)


def update_settings_permissions(settings_path: Path, allows: list, denies: list,
                                 dry_run: bool, skip_permissions: bool):
    """Merge permission entries into settings.json using append-missing semantics.

    Existing entries (including manually added ones) are preserved.
    New entries are appended. All entries are deduplicated and sorted.
    """
    if skip_permissions:
        print("Skipped: permissions management (--skip-permissions)")
        return

    if dry_run:
        print(f"> Would update {settings_path} permissions ({len(allows)} allow entries)")
        return

    # Read existing settings or start fresh
    existing = load_json(settings_path)

    existing_allows = existing.get("permissions", {}).get("allow", [])
    existing_denies = existing.get("permissions", {}).get("deny", [])

    merged_allows = sorted(set(existing_allows) | set(allows))
    merged_denies = sorted(set(existing_denies) | set(denies))

    if "permissions" not in existing:
        existing["permissions"] = {}
    existing["permissions"]["allow"] = merged_allows
    existing["permissions"]["deny"] = merged_denies

    _atomic_write_json(settings_path, existing)

    count = len(merged_allows)
    print(f"Updated: {settings_path} permissions ({count} allow entries)")


def update_settings_hooks(settings_path: Path, hook_configs: list,
                           hooks_base: Path, dry_run: bool,
                           skip_permissions: bool):
    """Build the hooks JSON object from collected hook configs and merge into settings.json.

    Uses append-missing semantics: existing event+matcher pairs are preserved;
    only new ones are added. Manually added hooks survive re-deployment.

    hook_configs: list of (hook_name, config_path) tuples
    """
    if skip_permissions:
        print("Skipped: hooks management (--skip-permissions)")
        return

    if not hook_configs:
        return

    # Build hooks dict grouped by event
    new_hooks = {}
    for hook_name, config_path in hook_configs:
        data = load_json(config_path)
        hc = data.get("hooks_config", {})
        if not hc:
            continue

        event = hc.get("event")
        matcher = hc.get("matcher")
        command_script = hc.get("command_script")
        async_flag = hc.get("async", False)
        timeout_val = hc.get("timeout")

        if not event or not matcher or not command_script:
            continue

        command_path = str(hooks_base / hook_name / command_script)

        hook_entry = {"type": "command", "command": command_path}
        if async_flag:
            hook_entry["async"] = True
        if timeout_val is not None:
            hook_entry["timeout"] = timeout_val

        matcher_group = {"matcher": matcher, "hooks": [hook_entry]}

        if event not in new_hooks:
            new_hooks[event] = []
        new_hooks[event].append(matcher_group)

    if dry_run:
        event_count = len(new_hooks)
        print(f"> Would update {settings_path} hooks ({event_count} events)")
        return

    # Read existing settings
    existing = load_json(settings_path)
    existing_hooks = existing.get("hooks", {})

    # Merge: preserve existing event+matcher pairs, add missing ones
    for event, groups in new_hooks.items():
        if event not in existing_hooks:
            existing_hooks[event] = []
        for group in groups:
            # Check if this matcher already exists under this event
            already_present = any(
                g.get("matcher") == group["matcher"]
                for g in existing_hooks[event]
            )
            if not already_present:
                existing_hooks[event].append(group)

    existing["hooks"] = existing_hooks
    _atomic_write_json(settings_path, existing)

    event_count = len(existing_hooks)
    print(f"Updated: {settings_path} hooks ({event_count} events)")


def _atomic_write_json(path: Path, data: dict):
    """Write JSON to path atomically via a tmp file + os.replace()."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(str(tmp), str(path))


# ---------------------------------------------------------------------------
# is_globally_deployed helper
# ---------------------------------------------------------------------------

def is_globally_deployed(md_path: Path, global_commands_base: Path) -> bool:
    """Return True if the skill .md is already deployed globally.

    Checks both top-level (single-md tools) and subdirectory (multi-md tools).
    """
    md_name = md_path.name
    tool_name = md_path.parent.name
    return (
        (global_commands_base / md_name).is_symlink()
        or (global_commands_base / tool_name / md_name).is_symlink()
    )


# ---------------------------------------------------------------------------
# Deploy loops
# ---------------------------------------------------------------------------

def deploy_skill(
    skill_dir,
    repo_root,
    profile_data,
    profile_new_items,
    include,
    exclude,
    project_path,
    cli_on_path,
    global_commands_base,
    tools_base,
    dry_run,
    deployed_configs,
    hook_configs,
):
    """Deploy a single skill directory. Returns True if deployed."""
    skill_dir = Path(skill_dir)
    skill_name = skill_dir.name

    if not check_condition(skill_dir):
        print(f"Skipped: {skill_name} (condition not met)")
        return False

    if is_filtered_out(skill_name, include, exclude):
        print(f"Skipped: {skill_name} (filtered out)")
        return False

    # Resolve config
    config = resolve_config(skill_dir, repo_root)

    # Track profile drift
    if profile_data and skill_name not in profile_data.get("skills", {}):
        profile_new_items.append(f"{skill_name} (skills)")

    config = apply_profile_overrides(config, profile_data, "skills", skill_name)

    if not config.get("enabled", True):
        print(f"Skipped: {skill_name} (disabled by config)")
        return False

    # Determine effective scope
    if project_path:
        effective_scope = "project"
    elif config.get("scope") == "project":
        print(f"Skipped: {skill_name} (scope=project, no --project flag given)")
        return False
    else:
        effective_scope = "global"

    # Determine effective on_path
    effective_on_path = cli_on_path or bool(config.get("on_path", False))

    # Determine commands base
    if effective_scope == "project":
        commands_base = Path(project_path) / ".claude" / "commands"
    else:
        commands_base = global_commands_base

    if dry_run:
        print(f"> mkdir -p {commands_base}")
    else:
        commands_base.mkdir(parents=True, exist_ok=True)

    # Deploy scripts: symlink skill directory to ~/.claude/tools/<skill-name>
    ensure_link(
        tools_base / skill_name,
        skill_dir,
        f"~/.claude/tools/{skill_name}",
        dry_run,
        for_dir=True,
    )

    # Deploy skills: symlink .md files (excluding README.md) to commands
    md_files = sorted(
        [md for md in skill_dir.glob("*.md") if md.name != "README.md"]
    )

    if len(md_files) == 1:
        md = md_files[0]
        md_name = md.name
        if effective_scope == "project" and is_globally_deployed(md, global_commands_base):
            print(f"Skipped: {skill_name} skill (already deployed globally)")
        else:
            ensure_link(
                commands_base / md_name,
                md,
                str(commands_base / md_name),
                dry_run,
            )
    elif len(md_files) > 1:
        # Multiple skills: create subdirectory and symlink each
        skip_count = 0
        if effective_scope == "project":
            skip_count = sum(
                1 for md in md_files
                if is_globally_deployed(md, global_commands_base)
            )

        if effective_scope == "project" and skip_count == len(md_files):
            print(f"Skipped: {skill_name} skills (already deployed globally)")
        else:
            subdir = commands_base / skill_name
            if dry_run:
                print(f"> mkdir -p {subdir}")
            else:
                subdir.mkdir(parents=True, exist_ok=True)

            for md in md_files:
                md_name = md.name
                if effective_scope == "project" and is_globally_deployed(md, global_commands_base):
                    print(f"Skipped: {skill_name}/{md_name} (already deployed globally)")
                else:
                    ensure_link(
                        subdir / md_name,
                        md,
                        str(subdir / md_name),
                        dry_run,
                    )

    # Clean up stale old-style directory symlink if present
    # Legacy deploy once symlinked the entire skill dir to commands/<skill-name>.
    # If that symlink still exists and points into skills/, remove it.
    old_link = commands_base / skill_name
    if old_link.is_symlink() and old_link.is_dir():
        try:
            link_target = str(old_link.readlink())
            if "/skills/" in link_target:
                if dry_run:
                    print(f"> rm {old_link}")
                else:
                    old_link.unlink()
                print(f"Cleaned: stale directory symlink {old_link}")
        except OSError:
            pass

    # Optionally symlink scripts to ~/.local/bin/
    if effective_on_path:
        bin_dir = skill_dir / "bin"
        if bin_dir.is_dir():
            local_bin = Path.home() / ".local" / "bin"
            if dry_run:
                print(f"> mkdir -p {local_bin}")
            else:
                local_bin.mkdir(parents=True, exist_ok=True)
            for script in sorted(bin_dir.iterdir()):
                if not script.is_file():
                    continue
                ensure_link(
                    local_bin / script.name,
                    script,
                    f"~/.local/bin/{script.name}",
                    dry_run,
                )

    # Collect permissions from this skill's config chain
    for cfg_name in ("deploy.json", "deploy.local.json"):
        p = skill_dir / cfg_name
        if p.exists():
            deployed_configs.append(p)

    # Deploy dependencies: symlink skill dirs + collect permissions, skip skills
    deps = config.get("dependencies", [])
    for dep in deps:
        if not dep:
            continue
        dep_dir = repo_root / "skills" / dep
        if not dep_dir.is_dir():
            print(f"Warning: dependency '{dep}' not found (required by {skill_name})")
            continue
        ensure_link(
            tools_base / dep,
            dep_dir,
            f"~/.claude/tools/{dep} (dependency of {skill_name})",
            dry_run,
            for_dir=True,
        )
        for cfg_name in ("deploy.json", "deploy.local.json"):
            p = dep_dir / cfg_name
            if p.exists():
                deployed_configs.append(p)

    print(f"Deployed: {skill_name}")
    return True


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

    if not check_condition(hook_dir):
        print(f"Skipped: hook {hook_name} (condition not met)")
        return False

    if is_filtered_out(hook_name, include, exclude):
        print(f"Skipped: hook {hook_name} (filtered out)")
        return False

    # Resolve config
    config = resolve_config(hook_dir, repo_root)

    # Track profile drift
    if profile_data and hook_name not in profile_data.get("hooks", {}):
        profile_new_items.append(f"{hook_name} (hooks)")

    config = apply_profile_overrides(config, profile_data, "hooks", hook_name)

    if not config.get("enabled", True):
        print(f"Skipped: hook {hook_name} (disabled by config)")
        return False

    ensure_link(
        hooks_base / hook_name,
        hook_dir,
        f"~/.claude/hooks/{hook_name}",
        dry_run,
        for_dir=True,
    )

    # Collect permissions from this hook's config chain
    for cfg_name in ("deploy.json", "deploy.local.json"):
        p = hook_dir / cfg_name
        if p.exists():
            deployed_configs.append(p)

    # Collect hook config for settings.json hooks wiring
    # hooks_config only from deploy.json (not deploy.local.json -- intentional)
    hook_deploy_json = hook_dir / "deploy.json"
    if hook_deploy_json.exists():
        data = load_json(hook_deploy_json)
        if "hooks_config" in data:
            hook_configs.append((hook_name, hook_deploy_json))

    print(f"Deployed: hook {hook_name}")
    return True


# ---------------------------------------------------------------------------
# Profile drift checking
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def print_usage():
    print("""Usage: ./deploy.py [OPTIONS]

Deploy Claude Code skills, tool scripts, and hooks.

Scripts are always deployed to ~/.claude/tools/<tool-name>/.
Skills (.md files) are deployed to ~/.claude/commands/ (or a project).
Hooks are always deployed to ~/.claude/hooks/<hook-name>/ (global only).

Options:
  --project PATH         Deploy skills to PATH/.claude/commands/ instead of globally
  --on-path              Also symlink scripts to ~/.local/bin/ (global deploy only)
  --profile PATH         Load a deployment profile (.deploy-profiles/*.json)
  --no-profile           Skip auto-loading .deploy-profiles/global.json
  --include tool1,tool2  Only deploy these tools (comma-separated)
  --exclude tool1,tool2  Deploy all tools EXCEPT these (comma-separated)
  --dry-run              Show what would be done without making any changes
  --skip-permissions     Skip settings.json permission management
  -h, --help             Show this help message

--include and --exclude are mutually exclusive. Tool names match directory
names under skills/ (e.g., jar-explore, docker-pg-query).

CLI flags override config file values. Per-tool config is read from JSON
files (see CLAUDE.md for details):
  deploy.json / deploy.local.json          (repo-wide)
  skills/<name>/deploy.json / .local.json  (per-skill)
  .deploy-profiles/*.json                  (deployment profiles)

When --project is used, skills already deployed globally (~/.claude/commands/)
are skipped to avoid conflicts.

Examples:
  ./deploy.py                                    Deploy all tools
  ./deploy.py --on-path                          Also symlink scripts to ~/.local/bin/
  ./deploy.py --project /path/to/repo            Deploy skills to a specific project
  ./deploy.py --include jar-explore              Deploy only jar-explore
  ./deploy.py --exclude image                     Deploy everything except image
  ./deploy.py --include jar-explore --on-path    Deploy jar-explore with PATH symlinks""")


def parse_args():
    parser = argparse.ArgumentParser(
        prog="./deploy.py",
        description="Deploy Claude Code skills, tool scripts, and hooks.",
        add_help=False,
    )
    parser.add_argument("--project", metavar="PATH", default="")
    parser.add_argument("--on-path", action="store_true", dest="on_path")
    parser.add_argument("--profile", metavar="PATH", default="")
    parser.add_argument("--no-profile", action="store_true")
    parser.add_argument("--include", metavar="tool1,tool2", default="")
    parser.add_argument("--exclude", metavar="tool1,tool2", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-permissions", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.help:
        print_usage()
        sys.exit(1)

    # --- Validate mutually exclusive / conflicting flags ---
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
    repo_root = Path(__file__).resolve().parent
    claude_config_dir = Path(
        os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))
    )

    project_path = Path(args.project).resolve() if args.project else None

    # --- Profile loading ---
    profile_path = ""
    profile_data = {}

    if args.profile:
        profile_file = Path(args.profile)
        if not profile_file.exists():
            print(f"Error: Profile not found: {args.profile}", file=sys.stderr)
            sys.exit(1)
        profile_path = str(profile_file)
        profile_data = load_json(profile_file)
    elif not args.no_profile:
        auto_profile = repo_root / ".deploy-profiles" / "global.json"
        if auto_profile.exists():
            profile_path = str(auto_profile)
            profile_data = load_json(auto_profile)

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

    # --- Base dirs ---
    global_commands_base = claude_config_dir / "commands"
    tools_base = claude_config_dir / "tools"
    hooks_base = claude_config_dir / "hooks"

    # --- Dry-run banner ---
    if args.dry_run:
        print("=== DRY RUN (no changes will be made) ===")
        print("")

    # --- Create base directories ---
    if args.dry_run:
        print(f"> mkdir -p {global_commands_base}")
        print(f"> mkdir -p {tools_base}")
    else:
        global_commands_base.mkdir(parents=True, exist_ok=True)
        tools_base.mkdir(parents=True, exist_ok=True)

    # --- Clean broken symlinks before deploying ---
    cleanup_broken_symlinks(tools_base, "dir", args.dry_run)
    cleanup_broken_symlinks(global_commands_base, "", args.dry_run)

    if project_path:
        project_commands = project_path / ".claude" / "commands"
        if args.dry_run:
            print(f"> mkdir -p {project_commands}")
        else:
            project_commands.mkdir(parents=True, exist_ok=True)
        cleanup_broken_symlinks(project_commands, "", args.dry_run)

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
    hook_configs = []  # (hook_name, config_path) pairs

    if not skills_dir.is_dir():
        print("No skills/ directory found.")
        update_settings_permissions(
            claude_config_dir / "settings.json",
            [], [],
            args.dry_run, args.skip_permissions,
        )
        return

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
            global_commands_base=global_commands_base,
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

    # --- Manage settings.json permissions ---
    print("")

    # Deduplicate config files (preserve order, first occurrence wins)
    seen_paths = set()
    unique_configs = []
    for p in deployed_configs:
        key = str(p)
        if key not in seen_paths:
            seen_paths.add(key)
            unique_configs.append(p)

    allows, denies = collect_permissions(unique_configs)

    # Permissions settings file: project when --project is given
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

    # --- Summary footer ---
    print("")
    if project_path:
        print(
            f"Deployed to: {project_path}/.claude/commands (project skills) + "
            f"~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
        )
    else:
        print("Deployed to: ~/.claude/commands (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)")

    if args.on_path:
        print("Scripts also linked to: ~/.local/bin (via --on-path flag)")

    if profile_path:
        print(f"Profile loaded: {profile_path}")

    # --- Check profile drift ---
    if profile_data:
        stale_items = check_profile_drift(seen_skills, seen_hooks, profile_data)

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


if __name__ == "__main__":
    main()
