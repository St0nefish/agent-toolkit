# deploy/deploy_skills.py - Skill deployment logic

from pathlib import Path

from deploy.common import collect_deploy_configs, pre_deploy_checks
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
        global_skills_base,
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
        skills_base = Path(project_path) / ".claude" / "skills"
    else:
        skills_base = global_skills_base

    if dry_run:
        print(f"  > mkdir -p {skills_base}")
    else:
        skills_base.mkdir(parents=True, exist_ok=True)

    ensure_link(
        tools_base / skill_name,
        skill_dir,
        f"~/.claude/tools/{skill_name}",
        dry_run,
        for_dir=True,
    )

    skills = _collect_skills(skill_dir, skill_name)

    # Deploy each skill as <deploy_name>/SKILL.md
    for deploy_name, md_path in skills:
        if effective_scope == "project" and is_globally_deployed(
            deploy_name, global_skills_base
        ):
            print(f"  Skipped: {deploy_name} (already deployed globally)")
            continue

        subdir = skills_base / deploy_name
        if dry_run:
            print(f"  > mkdir -p {subdir}")
        else:
            subdir.mkdir(parents=True, exist_ok=True)

        ensure_link(
            subdir / "SKILL.md",
            md_path,
            str(subdir / "SKILL.md"),
            dry_run,
        )

    # Clean up stale old-style symlinks (flat .md or directory-of-.md layouts)
    _cleanup_stale_skill_links(skills_base, skill_name, dry_run)

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

    collect_deploy_configs(skill_dir, deployed_configs)

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
        collect_deploy_configs(dep_dir, deployed_configs)

    print(f"  Deployed: {skill_name}")
    return True


def _collect_skills(skill_dir, skill_name):
    """Collect deployable skills from a skill directory.

    Supports two source layouts:

      Legacy (loose .md files):
        skills/session/start.md        → ("session-start", .../start.md)
        skills/catchup/catchup.md      → ("catchup", .../catchup.md)

      Modern (subdirectories with SKILL.md):
        skills/session/start/SKILL.md  → ("session-start", .../start/SKILL.md)
        skills/session/end/SKILL.md    → ("session-end", .../end/SKILL.md)

    Returns a sorted list of (deploy_name, md_path) tuples.
    Both patterns produce the same deployment layout: <deploy_name>/SKILL.md
    """
    skills = []

    # Modern pattern: subdirectories containing SKILL.md
    for subdir in sorted(skill_dir.iterdir()):
        if not subdir.is_dir() or subdir.name == "bin":
            continue
        skill_md = subdir / "SKILL.md"
        if skill_md.is_file():
            skills.append((f"{skill_name}-{subdir.name}", skill_md))

    # Legacy pattern: loose .md files (excluding README.md)
    md_files = sorted(
        md for md in skill_dir.glob("*.md") if md.name != "README.md"
    )

    if skills and md_files:
        # Both patterns present — only use modern, ignore loose .md files
        return skills

    if md_files:
        if len(md_files) == 1:
            skills.append((skill_name, md_files[0]))
        else:
            for md in md_files:
                skills.append((f"{skill_name}-{md.stem}", md))

    return skills


def _cleanup_stale_skill_links(skills_base, skill_name, dry_run):
    """Remove old-style skill layouts that the new SKILL.md format replaces.

    Old layouts:
      - Flat symlink:  skills_base/<name>.md
      - Colon-namespaced dir: skills_base/<name>/<stem>.md
      - Directory symlink: skills_base/<name> → skills/<name>/
    """
    # Flat .md symlink (old single-md layout)
    flat = skills_base / f"{skill_name}.md"
    if flat.is_symlink():
        if dry_run:
            print(f"  > rm {flat}")
        else:
            flat.unlink()
        print(f"  Cleaned: stale flat symlink {flat}")

    # Colon-namespaced subdirectory (old multi-md layout)
    old_subdir = skills_base / skill_name
    if old_subdir.is_dir() and not old_subdir.is_symlink():
        for entry in list(old_subdir.iterdir()):
            if entry.is_symlink() and entry.name != "SKILL.md":
                if dry_run:
                    print(f"  > rm {entry}")
                else:
                    entry.unlink()
                print(f"  Cleaned: stale symlink {entry}")
        # Remove directory if now empty
        if not any(old_subdir.iterdir()):
            if dry_run:
                print(f"  > rmdir {old_subdir}")
            else:
                try:
                    old_subdir.rmdir()
                except OSError:
                    pass
            print(f"  Cleaned: stale directory {old_subdir}")

    # Directory symlink pointing at source (very old layout)
    if old_subdir.is_symlink() and old_subdir.is_dir():
        try:
            link_target = str(old_subdir.readlink())
            if "/skills/" in link_target:
                if dry_run:
                    print(f"  > rm {old_subdir}")
                else:
                    old_subdir.unlink()
                print(f"  Cleaned: stale directory symlink {old_subdir}")
        except OSError:
            pass
