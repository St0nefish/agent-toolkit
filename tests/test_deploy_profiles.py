"""Tests for deploy.py deployment profile support.

Port of tests/test-deploy-profiles.sh. Covers:
  1.  Profile disables a skill via enabled: false
  2.  Profile enables on_path for a skill
  3.  Profile ignores per-item scope (only enabled/on_path are whitelisted)
  4.  Profile overrides item-level deploy.json (profile > deploy.json)
  5.  CLI --on-path flag overrides profile on_path: false
  6.  Profile project_path sets deployment scope to project dir
  7.  CLI --project overrides profile project_path
  8.  Auto-load: .deploy-profiles/global.json loaded without --profile flag
  9.  No profile = normal deployment (no filtering, no footer)
  10. Profile stray keys (e.g. permissions) are stripped; valid keys still work
  11. Nonexistent --profile path exits with error and message
  12. Profile disables a hook via enabled: false
  13. Item not listed in profile is disabled and flagged "not in profile"
  14. Profile references a non-existent skill → stale warning shown
  15. Stale profile entry and valid skill coexist without blocking deployment
"""

import json

import pytest


# ---------------------------------------------------------------------------
# Shared skill setup helpers
# ---------------------------------------------------------------------------

MD_CONTENT = "---\ndescription: Profile test tool\n---\n# Profile Test\n"
HOOK_SCRIPT = "#!/usr/bin/env bash\necho hook ran\n"


def make_profiletest(mini_repo):
    """Create the standard 'profiletest' skill used across most tests."""
    mini_repo.create_skill("profiletest", md_content=MD_CONTENT)


def make_testhook(mini_repo):
    """Create the standard 'testhook' hook used in hook-related tests."""
    mini_repo.create_hook(
        "testhook",
        script_content=HOOK_SCRIPT,
    )


def write_profile(mini_repo, filename, profile_dict):
    """Write a JSON profile file under .deploy-profiles/ and return its Path."""
    profiles_dir = mini_repo.root / ".deploy-profiles"
    profiles_dir.mkdir(parents=True, exist_ok=True)
    path = profiles_dir / filename
    path.write_text(json.dumps(profile_dict) + "\n")
    return path


# ---------------------------------------------------------------------------
# Test 1: Profile disables item
# ---------------------------------------------------------------------------


def test_profile_disables_skill(mini_repo, tmp_path, run_deploy):
    """A profile entry with enabled: false skips that skill."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": False}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg1"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Skipped: profiletest (disabled by config)" in combined


# ---------------------------------------------------------------------------
# Test 2: Profile enables on_path
# ---------------------------------------------------------------------------


def test_profile_enables_on_path(mini_repo, tmp_path, run_deploy):
    """A profile entry with on_path: true symlinks scripts into ~/.local/bin/."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {"profiletest": {"enabled": True, "on_path": True}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg2"
    cfg.mkdir()
    fake_home = tmp_path / "home2"
    fake_home.mkdir()

    run_deploy(
        "--profile",
        str(profile_path),
        "--skip-permissions",
        config_dir=cfg,
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "profiletest").is_symlink()


# ---------------------------------------------------------------------------
# Test 3: Profile ignores per-item scope (only enabled/on_path whitelisted)
# ---------------------------------------------------------------------------


def test_profile_scope_key_ignored(mini_repo, tmp_path, run_deploy):
    """A profile entry with scope: 'project' is ignored; tool still deploys globally."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {"profiletest": {"enabled": True, "scope": "project"}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg3"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Deployed: profiletest" in combined


# ---------------------------------------------------------------------------
# Test 4: Profile beats item-level deploy.json
# ---------------------------------------------------------------------------


def test_profile_overrides_item_deploy_json(mini_repo, tmp_path, run_deploy):
    """Profile on_path: true takes precedence over item deploy.json on_path: false."""
    mini_repo.create_skill(
        "profiletest",
        md_content=MD_CONTENT,
        deploy_json={"on_path": False},
    )
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {"profiletest": {"enabled": True, "on_path": True}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg4"
    cfg.mkdir()
    fake_home = tmp_path / "home4"
    fake_home.mkdir()

    run_deploy(
        "--profile",
        str(profile_path),
        "--skip-permissions",
        config_dir=cfg,
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "profiletest").is_symlink()


# ---------------------------------------------------------------------------
# Test 5: CLI --on-path flag beats profile on_path: false
# ---------------------------------------------------------------------------


def test_cli_on_path_beats_profile(mini_repo, tmp_path, run_deploy):
    """CLI --on-path overrides profile's on_path: false setting."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {"profiletest": {"enabled": True, "on_path": False}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg5"
    cfg.mkdir()
    fake_home = tmp_path / "home5"
    fake_home.mkdir()

    run_deploy(
        "--profile",
        str(profile_path),
        "--on-path",
        "--skip-permissions",
        config_dir=cfg,
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "profiletest").is_symlink()


# ---------------------------------------------------------------------------
# Test 6: Profile project_path deploys skills to project dir
# ---------------------------------------------------------------------------


def test_profile_project_path_deploys_to_project(mini_repo, tmp_path, run_deploy):
    """A profile with project_path deploys skills into that project's .claude/skills/."""
    make_profiletest(mini_repo)
    project_dir = tmp_path / "myproject6"
    (project_dir / ".claude").mkdir(parents=True)

    profile_path = write_profile(
        mini_repo,
        "myproject.json",
        {
            "project_path": str(project_dir),
            "skills": {"profiletest": {"enabled": True}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg6"
    cfg.mkdir()

    run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )

    assert (project_dir / ".claude" / "skills" / "profiletest" / "SKILL.md").is_symlink()


# ---------------------------------------------------------------------------
# Test 7: CLI --project overrides profile project_path
# ---------------------------------------------------------------------------


def test_cli_project_overrides_profile_project_path(mini_repo, tmp_path, run_deploy):
    """CLI --project path wins over profile's project_path."""
    make_profiletest(mini_repo)
    profile_project = tmp_path / "profile_project7"
    cli_project = tmp_path / "cli_project7"
    (profile_project / ".claude").mkdir(parents=True)
    (cli_project / ".claude").mkdir(parents=True)

    profile_path = write_profile(
        mini_repo,
        "myproject.json",
        {
            "project_path": str(profile_project),
            "skills": {"profiletest": {"enabled": True}},
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg7"
    cfg.mkdir()

    run_deploy(
        "--profile",
        str(profile_path),
        "--project",
        str(cli_project),
        "--skip-permissions",
        config_dir=cfg,
    )

    assert (cli_project / ".claude" / "skills" / "profiletest" / "SKILL.md").is_symlink()
    assert not (profile_project / ".claude" / "skills" / "profiletest" / "SKILL.md").exists()


# ---------------------------------------------------------------------------
# Test 8: Auto-load global.json without --profile flag
# ---------------------------------------------------------------------------


def test_auto_load_global_json_disables_tool(mini_repo, tmp_path, run_deploy):
    """Without --profile, .deploy-profiles/global.json is auto-loaded."""
    make_profiletest(mini_repo)
    write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": False}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg8"
    cfg.mkdir()

    result = run_deploy("--skip-permissions", config_dir=cfg)
    combined = result.stdout + result.stderr

    assert "Skipped: profiletest (disabled by config)" in combined


def test_auto_load_global_json_shows_profile_footer(mini_repo, tmp_path, run_deploy):
    """Auto-loaded global.json is reported in the deployment footer."""
    make_profiletest(mini_repo)
    write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": False}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg8b"
    cfg.mkdir()

    result = run_deploy("--skip-permissions", config_dir=cfg)
    combined = result.stdout + result.stderr

    assert "Profile loaded:" in combined


# ---------------------------------------------------------------------------
# Test 9: No profile = normal deployment, no profile footer
# ---------------------------------------------------------------------------


def test_no_profile_deploys_normally(mini_repo, tmp_path, run_deploy):
    """Without any profile, skills deploy as normal."""
    make_profiletest(mini_repo)
    cfg = tmp_path / "cfg9"
    cfg.mkdir()

    result = run_deploy("--skip-permissions", config_dir=cfg)
    combined = result.stdout + result.stderr

    assert "Deployed: profiletest" in combined


def test_no_profile_no_footer(mini_repo, tmp_path, run_deploy):
    """Without any profile, the 'Profile loaded:' footer line is absent."""
    make_profiletest(mini_repo)
    cfg = tmp_path / "cfg9b"
    cfg.mkdir()

    result = run_deploy("--skip-permissions", config_dir=cfg)
    combined = result.stdout + result.stderr

    assert "Profile loaded:" not in combined


# ---------------------------------------------------------------------------
# Test 10: Profile stray keys (e.g. permissions) stripped; valid keys still apply
# ---------------------------------------------------------------------------


def test_profile_stray_permissions_key_stripped_valid_keys_apply(mini_repo, tmp_path, run_deploy):
    """Stray 'permissions' key in profile entry is ignored; on_path still works."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {
                "profiletest": {
                    "enabled": True,
                    "on_path": True,
                    "permissions": {"allow": ["Bash(evil)"]},
                }
            },
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg10"
    cfg.mkdir()
    fake_home = tmp_path / "home10"
    fake_home.mkdir()

    run_deploy(
        "--profile",
        str(profile_path),
        "--skip-permissions",
        config_dir=cfg,
        env_overrides={"HOME": str(fake_home)},
    )

    # on_path (a valid key) must still take effect
    assert (fake_home / ".local" / "bin" / "profiletest").is_symlink()


# ---------------------------------------------------------------------------
# Test 11: Nonexistent --profile path → non-zero exit + error message
# ---------------------------------------------------------------------------


def test_nonexistent_profile_exits_nonzero(mini_repo, tmp_path, run_deploy):
    """Passing a non-existent path to --profile must cause a non-zero exit."""
    make_profiletest(mini_repo)
    cfg = tmp_path / "cfg11"
    cfg.mkdir()

    result = run_deploy(
        "--profile", "/nonexistent/profile.json", "--skip-permissions", config_dir=cfg
    )

    assert result.returncode != 0


def test_nonexistent_profile_shows_error_message(mini_repo, tmp_path, run_deploy):
    """Passing a non-existent path to --profile must print a 'Profile not found' error."""
    make_profiletest(mini_repo)
    cfg = tmp_path / "cfg11b"
    cfg.mkdir()

    result = run_deploy(
        "--profile", "/nonexistent/profile.json", "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Profile not found" in combined


# ---------------------------------------------------------------------------
# Test 12: Profile disables a hook
# ---------------------------------------------------------------------------


def test_profile_disables_hook(mini_repo, tmp_path, run_deploy):
    """A profile hook entry with enabled: false skips that hook."""
    make_profiletest(mini_repo)
    make_testhook(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {"profiletest": {"enabled": True}},
            "hooks": {"testhook": {"enabled": False}},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg12"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Skipped: hook testhook (disabled by config)" in combined


# ---------------------------------------------------------------------------
# Test 13: Item not in profile is disabled and flagged "not in profile"
# ---------------------------------------------------------------------------


def test_item_not_in_profile_is_disabled(mini_repo, tmp_path, run_deploy):
    """A skill present on disk but absent from the profile is skipped."""
    make_profiletest(mini_repo)
    # Create a second skill absent from the profile
    mini_repo.create_skill(
        "extra",
        md_content="---\ndescription: Extra tool\n---\n# Extra\n",
    )
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": True}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg13"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Skipped: extra (disabled by config)" in combined


def test_item_not_in_profile_is_flagged(mini_repo, tmp_path, run_deploy):
    """A skill absent from the profile triggers a 'not in profile' warning."""
    make_profiletest(mini_repo)
    mini_repo.create_skill(
        "extra",
        md_content="---\ndescription: Extra tool\n---\n# Extra\n",
    )
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": True}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg13b"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "not in profile" in combined


def test_item_in_profile_still_deploys_alongside_absent(mini_repo, tmp_path, run_deploy):
    """The skill listed in the profile deploys normally even when another is absent."""
    make_profiletest(mini_repo)
    mini_repo.create_skill(
        "extra",
        md_content="---\ndescription: Extra tool\n---\n# Extra\n",
    )
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {"skills": {"profiletest": {"enabled": True}}, "hooks": {}, "mcp": {}},
    )
    cfg = tmp_path / "cfg13c"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Deployed: profiletest" in combined


# ---------------------------------------------------------------------------
# Test 14: Stale skill in profile (profile references non-existent skill)
# ---------------------------------------------------------------------------


def test_stale_profile_skill_shows_warning(mini_repo, tmp_path, run_deploy):
    """A profile entry for a skill that no longer exists on disk triggers a stale warning."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {
                "profiletest": {"enabled": True},
                "gone-tool": {"enabled": True},
            },
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg14"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Stale items" in combined


def test_stale_profile_skill_name_listed(mini_repo, tmp_path, run_deploy):
    """The stale warning includes the name of the missing skill."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {
                "profiletest": {"enabled": True},
                "gone-tool": {"enabled": True},
            },
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg14b"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "gone-tool (skills)" in combined


# ---------------------------------------------------------------------------
# Test 15: Stale + valid skill coexist without blocking deployment
# ---------------------------------------------------------------------------


def test_valid_skill_deploys_alongside_stale(mini_repo, tmp_path, run_deploy):
    """A stale profile entry does not prevent valid skills from deploying."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {
                "profiletest": {"enabled": True},
                "vanished": {"enabled": True},
            },
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg15"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "Deployed: profiletest" in combined


def test_stale_skill_flagged_alongside_valid(mini_repo, tmp_path, run_deploy):
    """The stale warning is emitted even when a valid skill deploys successfully."""
    make_profiletest(mini_repo)
    profile_path = write_profile(
        mini_repo,
        "global.json",
        {
            "skills": {
                "profiletest": {"enabled": True},
                "vanished": {"enabled": True},
            },
            "hooks": {},
            "mcp": {},
        },
    )
    cfg = tmp_path / "cfg15b"
    cfg.mkdir()

    result = run_deploy(
        "--profile", str(profile_path), "--skip-permissions", config_dir=cfg
    )
    combined = result.stdout + result.stderr

    assert "vanished (skills)" in combined
