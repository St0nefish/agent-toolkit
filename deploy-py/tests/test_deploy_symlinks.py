"""Tests for deploy.py symlink creation and layout.

Port of tests/test-deploy-symlinks.sh. Covers:
  1. Single .md → skills/<name>.md symlink
  2. Multi .md → skills/<tool-name>/ subdirectory with symlinks inside
  3. README.md excluded from deployment
  4. Tool dirs symlinked to tools/
  5. Hook dir symlinked to hooks/
  6. --on-path symlinks scripts to ~/.local/bin/
  7. --project deploys skills to project path (tool dirs still global)
  8. --dry-run creates no symlinks but shows output
"""

import pytest


# ---------------------------------------------------------------------------
# Fixtures — shared mini-repo setup
# ---------------------------------------------------------------------------


def _make_script(path, content="#!/usr/bin/env bash\necho hello\n"):
    path.write_text(content)
    path.chmod(0o755)


@pytest.fixture
def repo(mini_repo):
    """Mini-repo pre-populated with the skills and hook used across tests."""
    # Tool "single" — one .md file, one bin script
    single_dir = mini_repo.root / "skills" / "single"
    bin_dir = single_dir / "bin"
    bin_dir.mkdir(parents=True)
    _make_script(bin_dir / "single-script")
    (single_dir / "single.md").write_text(
        "---\ndescription: Single skill tool\n---\n# Single\n"
    )

    # Tool "multi" — two .md files (start.md + stop.md), one bin script
    multi_dir = mini_repo.root / "skills" / "multi"
    bin_dir = multi_dir / "bin"
    bin_dir.mkdir(parents=True)
    _make_script(bin_dir / "multi-script")
    (multi_dir / "start.md").write_text(
        "---\ndescription: Multi start skill\n---\n# Start\n"
    )
    (multi_dir / "stop.md").write_text(
        "---\ndescription: Multi stop skill\n---\n# Stop\n"
    )

    # Tool "with-readme" — one real .md + README.md (README excluded from deploy)
    readme_dir = mini_repo.root / "skills" / "with-readme"
    bin_dir = readme_dir / "bin"
    bin_dir.mkdir(parents=True)
    _make_script(bin_dir / "readme-script")
    (readme_dir / "with-readme.md").write_text(
        "---\ndescription: Tool with readme\n---\n# With Readme\n"
    )
    (readme_dir / "README.md").write_text(
        "# Developer notes — should not be deployed as a skill\n"
    )

    # Hook "test-hook"
    hook_dir = mini_repo.root / "hooks" / "test-hook"
    hook_dir.mkdir(parents=True)
    _make_script(hook_dir / "hook.sh", "#!/usr/bin/env bash\nexit 0\n")

    return mini_repo


# ---------------------------------------------------------------------------
# Test: basic symlink layout
# ---------------------------------------------------------------------------


def test_single_md_symlink(repo, config_dir, run_deploy):
    """Single .md file → skills/<name>/SKILL.md symlink."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "single" / "SKILL.md").is_symlink()


def test_multi_md_start_skill_dir(repo, config_dir, run_deploy):
    """Multiple .md files → skills/multi-start/SKILL.md symlink."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "multi-start" / "SKILL.md").is_symlink()


def test_multi_md_stop_skill_dir(repo, config_dir, run_deploy):
    """Multiple .md files → skills/multi-stop/SKILL.md symlink."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "multi-stop" / "SKILL.md").is_symlink()


def test_readme_excluded_from_skills(repo, config_dir, run_deploy):
    """README.md is never deployed as a skill."""
    run_deploy("--skip-permissions")
    assert not (config_dir / "skills" / "with-readme-README" / "SKILL.md").exists()


def test_real_skill_deployed_alongside_readme(repo, config_dir, run_deploy):
    """The real .md skill still deploys when README.md is present and excluded."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "with-readme" / "SKILL.md").is_symlink()


def test_tool_dirs_symlinked(repo, config_dir, run_deploy):
    """Each skill directory is symlinked into tools/."""
    run_deploy("--skip-permissions")
    assert (config_dir / "tools" / "single").is_symlink()
    assert (config_dir / "tools" / "multi").is_symlink()


def test_hook_dir_symlinked(repo, config_dir, run_deploy):
    """Hook directory is symlinked into hooks/."""
    run_deploy("--skip-permissions")
    assert (config_dir / "hooks" / "test-hook").is_symlink()


# ---------------------------------------------------------------------------
# Test: modern SKILL.md subdirectory source layout
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_modern(mini_repo):
    """Mini-repo with a skill using modern group/sub/SKILL.md layout."""
    group_dir = mini_repo.root / "skills" / "workflow"

    start_dir = group_dir / "start"
    start_dir.mkdir(parents=True)
    (start_dir / "SKILL.md").write_text(
        "---\ndescription: Workflow start\n---\n# Start\n"
    )

    finish_dir = group_dir / "finish"
    finish_dir.mkdir(parents=True)
    (finish_dir / "SKILL.md").write_text(
        "---\ndescription: Workflow finish\n---\n# Finish\n"
    )

    bin_dir = group_dir / "bin"
    bin_dir.mkdir(parents=True)
    _make_script(bin_dir / "workflow-script")

    return mini_repo


def test_modern_layout_start_deployed(repo_modern, config_dir, run_deploy):
    """Modern layout: group/start/SKILL.md → skills/workflow-start/SKILL.md."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "workflow-start" / "SKILL.md").is_symlink()


def test_modern_layout_finish_deployed(repo_modern, config_dir, run_deploy):
    """Modern layout: group/finish/SKILL.md → skills/workflow-finish/SKILL.md."""
    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "workflow-finish" / "SKILL.md").is_symlink()


def test_modern_layout_tool_dir_symlinked(repo_modern, config_dir, run_deploy):
    """Modern layout: tool directory is still symlinked to tools/."""
    run_deploy("--skip-permissions")
    assert (config_dir / "tools" / "workflow").is_symlink()


def test_modern_layout_bin_not_deployed_as_skill(repo_modern, config_dir, run_deploy):
    """Modern layout: bin/ directory is not treated as a skill."""
    run_deploy("--skip-permissions")
    assert not (config_dir / "skills" / "workflow-bin" / "SKILL.md").exists()


def test_modern_single_subdir(mini_repo, config_dir, run_deploy):
    """Modern layout with one subdirectory still uses group-name prefix."""
    group_dir = mini_repo.root / "skills" / "solo"
    sub = group_dir / "only"
    sub.mkdir(parents=True)
    (sub / "SKILL.md").write_text(
        "---\ndescription: Solo only\n---\n# Only\n"
    )

    run_deploy("--skip-permissions")
    assert (config_dir / "skills" / "solo-only" / "SKILL.md").is_symlink()


def test_mixed_layout_modern_wins(mini_repo, config_dir, run_deploy):
    """When both loose .md and subdirs with SKILL.md exist, modern pattern wins."""
    group_dir = mini_repo.root / "skills" / "mixed"
    group_dir.mkdir(parents=True)

    # Loose .md (legacy)
    (group_dir / "legacy.md").write_text(
        "---\ndescription: Legacy\n---\n# Legacy\n"
    )

    # Subdir with SKILL.md (modern)
    sub = group_dir / "modern"
    sub.mkdir()
    (sub / "SKILL.md").write_text(
        "---\ndescription: Modern\n---\n# Modern\n"
    )

    run_deploy("--skip-permissions")

    # Modern skill deployed
    assert (config_dir / "skills" / "mixed-modern" / "SKILL.md").is_symlink()
    # Legacy loose .md NOT deployed (modern takes priority)
    assert not (config_dir / "skills" / "mixed-legacy" / "SKILL.md").exists()
    assert not (config_dir / "skills" / "mixed" / "SKILL.md").exists()


# ---------------------------------------------------------------------------
# Test: --on-path
# ---------------------------------------------------------------------------


def test_on_path_scripts_in_local_bin(repo, config_dir, run_deploy, tmp_path):
    """--on-path symlinks each bin/ script to ~/.local/bin/."""
    fake_home = tmp_path / "fake_home"
    fake_home.mkdir()

    run_deploy(
        "--on-path",
        "--skip-permissions",
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "single-script").is_symlink()
    assert (fake_home / ".local" / "bin" / "multi-script").is_symlink()


# ---------------------------------------------------------------------------
# Test: --project
# ---------------------------------------------------------------------------


def test_project_skill_in_project_skills(repo, config_dir, run_deploy, tmp_path):
    """--project deploys skills into <project>/.claude/skills/."""
    project_dir = tmp_path / "my_project"
    project_dir.mkdir()

    run_deploy("--project", str(project_dir), "--skip-permissions")

    assert (project_dir / ".claude" / "skills" / "single" / "SKILL.md").is_symlink()


def test_project_tool_dirs_still_global(repo, config_dir, run_deploy, tmp_path):
    """--project: tool directories still go to the global tools/ directory."""
    project_dir = tmp_path / "my_project"
    project_dir.mkdir()

    run_deploy("--project", str(project_dir), "--skip-permissions")

    assert (config_dir / "tools" / "single").is_symlink()


def test_project_skill_not_in_global_skills(repo, config_dir, run_deploy, tmp_path):
    """--project: skills must NOT appear in the global skills/ directory."""
    project_dir = tmp_path / "my_project"
    project_dir.mkdir()

    run_deploy("--project", str(project_dir), "--skip-permissions")

    assert not (config_dir / "skills" / "single" / "SKILL.md").exists()


# ---------------------------------------------------------------------------
# Test: --dry-run
# ---------------------------------------------------------------------------


def test_dry_run_no_tool_symlinks(repo, config_dir, run_deploy):
    """--dry-run must not create any tool symlinks."""
    run_deploy("--dry-run", "--skip-permissions")
    assert not (config_dir / "tools" / "single").is_symlink()


def test_dry_run_no_skill_symlinks(repo, config_dir, run_deploy):
    """--dry-run must not create any skill symlinks."""
    run_deploy("--dry-run", "--skip-permissions")
    assert not (config_dir / "skills" / "single" / "SKILL.md").exists()


def test_dry_run_output_has_arrow_lines(repo, config_dir, run_deploy):
    """--dry-run output contains lines prefixed with '> ' describing planned actions."""
    result = run_deploy("--dry-run", "--skip-permissions")
    combined = result.stdout + result.stderr
    assert any(line.startswith("> ") for line in combined.splitlines())


def test_dry_run_output_has_banner(repo, config_dir, run_deploy):
    """--dry-run output contains a 'DRY RUN' banner."""
    result = run_deploy("--dry-run", "--skip-permissions")
    combined = result.stdout + result.stderr
    assert "DRY RUN" in combined
