# deploy/deploy_skills.py - Skill deployment logic

from pathlib import Path

from deploy.common import pre_deploy_checks
from deploy.config import load_json
from deploy.linker import ensure_link, is_globally_deployed


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

    config, skip_reason = pre_deploy_checks(
        skill_dir, "skills", repo_root, profile_data,
        profile_new_items, include, exclude,
    )
    if skip_reason:
        print(f"  {skip_reason}")
        return False

    if project_path:
        effective_scope = "project"
    elif config.get("scope") == "project":
        print(f"  Skipped: {skill_name} (scope=project, no --project flag given)")
        return False
    else:
        effective_scope = "global"

    effective_on_path = cli_on_path or bool(config.get("on_path", False))

    if effective_scope == "project":
        commands_base = Path(project_path) / ".claude" / "commands"
    else:
        commands_base = global_commands_base

    if dry_run:
        print(f"  > mkdir -p {commands_base}")
    else:
        commands_base.mkdir(parents=True, exist_ok=True)

    ensure_link(
        tools_base / skill_name,
        skill_dir,
        f"~/.claude/tools/{skill_name}",
        dry_run,
        for_dir=True,
    )

    md_files = sorted(
        [md for md in skill_dir.glob("*.md") if md.name != "README.md"]
    )

    if len(md_files) == 1:
        md = md_files[0]
        md_name = md.name
        if effective_scope == "project" and is_globally_deployed(md, global_commands_base):
            print(f"  Skipped: {skill_name} skill (already deployed globally)")
        else:
            ensure_link(
                commands_base / md_name,
                md,
                str(commands_base / md_name),
                dry_run,
            )
    elif len(md_files) > 1:
        skip_count = 0
        if effective_scope == "project":
            skip_count = sum(
                1 for md in md_files
                if is_globally_deployed(md, global_commands_base)
            )

        if effective_scope == "project" and skip_count == len(md_files):
            print(f"  Skipped: {skill_name} skills (already deployed globally)")
        else:
            subdir = commands_base / skill_name
            if dry_run:
                print(f"  > mkdir -p {subdir}")
            else:
                subdir.mkdir(parents=True, exist_ok=True)

            for md in md_files:
                md_name = md.name
                if effective_scope == "project" and is_globally_deployed(md, global_commands_base):
                    print(f"  Skipped: {skill_name}/{md_name} (already deployed globally)")
                else:
                    ensure_link(
                        subdir / md_name,
                        md,
                        str(subdir / md_name),
                        dry_run,
                    )

    # Clean up stale old-style directory symlink if present
    old_link = commands_base / skill_name
    if old_link.is_symlink() and old_link.is_dir():
        try:
            link_target = str(old_link.readlink())
            if "/skills/" in link_target:
                if dry_run:
                    print(f"  > rm {old_link}")
                else:
                    old_link.unlink()
                print(f"  Cleaned: stale directory symlink {old_link}")
        except OSError:
            pass

    if effective_on_path:
        bin_dir = skill_dir / "bin"
        if bin_dir.is_dir():
            local_bin = Path.home() / ".local" / "bin"
            if dry_run:
                print(f"  > mkdir -p {local_bin}")
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

    for cfg_name in ("deploy.json", "deploy.local.json"):
        p = skill_dir / cfg_name
        if p.exists():
            deployed_configs.append(p)

    deps = config.get("dependencies", [])
    for dep in deps:
        if not dep:
            continue
        dep_dir = repo_root / "skills" / dep
        if not dep_dir.is_dir():
            print(f"  Warning: dependency '{dep}' not found (required by {skill_name})")
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

    print(f"  Deployed: {skill_name}")
    return True
