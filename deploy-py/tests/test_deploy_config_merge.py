"""Tests for deploy.py config layer merging (resolve_config behavior).

Port of tests/test-deploy-config-merge.sh. Covers config precedence:
  repo-root deploy.json
    < repo-root deploy.local.json
    < tool deploy.json
    < tool deploy.local.json
    < CLI flags
"""

import json


MD_CONTENT = "---\ndescription: Config test tool\n---\n# Config Test\n"


# ---------------------------------------------------------------------------
# Test 1: tool deploy.json overrides repo-root deploy.json
# ---------------------------------------------------------------------------


def test_tool_deploy_json_overrides_repo_root(mini_repo, config_dir, run_deploy, tmp_path):
    """Tool-level on_path: true wins over repo-root on_path: false."""
    mini_repo.create_skill("configtest", md_content=MD_CONTENT)
    mini_repo.create_deploy_json({"on_path": False})
    (mini_repo.root / "skills" / "configtest" / "deploy.json").write_text(
        json.dumps({"on_path": True}) + "\n"
    )

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir()

    run_deploy(
        "--skip-permissions",
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "configtest").is_symlink()


# ---------------------------------------------------------------------------
# Test 2: tool deploy.local.json overrides tool deploy.json
# ---------------------------------------------------------------------------


def test_tool_deploy_local_json_overrides_tool_deploy_json(
    mini_repo, config_dir, run_deploy
):
    """deploy.local.json enabled: false wins over deploy.json enabled: true."""
    skill_dir = mini_repo.create_skill("configtest", md_content=MD_CONTENT)
    (skill_dir / "deploy.json").write_text(json.dumps({"enabled": True}) + "\n")
    (skill_dir / "deploy.local.json").write_text(json.dumps({"enabled": False}) + "\n")

    result = run_deploy("--skip-permissions")

    combined = result.stdout + result.stderr
    assert "Skipped: configtest (disabled by config)" in combined


# ---------------------------------------------------------------------------
# Test 3: on_path: true in config works without --on-path CLI flag
# ---------------------------------------------------------------------------


def test_on_path_true_in_config_without_cli_flag(
    mini_repo, config_dir, run_deploy, tmp_path
):
    """on_path: true in deploy.json deploys to ~/.local/bin/ without --on-path."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={"on_path": True},
    )

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir()

    run_deploy(
        "--skip-permissions",
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "configtest").is_symlink()


# ---------------------------------------------------------------------------
# Test 4: scope: project skips tool when no --project flag is given
# ---------------------------------------------------------------------------


def test_scope_project_skips_without_project_flag(
    mini_repo, config_dir, run_deploy
):
    """scope: project causes the tool to be skipped when --project is absent."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={"scope": "project"},
    )

    result = run_deploy("--skip-permissions")

    combined = result.stdout + result.stderr
    assert "Skipped: configtest (scope=project, no --project flag given)" in combined


def test_scope_project_no_skill_symlink_created(
    mini_repo, config_dir, run_deploy
):
    """scope: project: no skill symlink is created in skills/."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={"scope": "project"},
    )

    run_deploy("--skip-permissions")

    assert not (config_dir / "skills" / "configtest" / "SKILL.md").exists()


# ---------------------------------------------------------------------------
# Test 5: CLI --on-path overrides config on_path: false
# ---------------------------------------------------------------------------


def test_cli_on_path_overrides_config_on_path_false(
    mini_repo, config_dir, run_deploy, tmp_path
):
    """--on-path CLI flag overrides deploy.json on_path: false."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={"on_path": False},
    )

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir()

    run_deploy(
        "--on-path",
        "--skip-permissions",
        env_overrides={"HOME": str(fake_home)},
    )

    assert (fake_home / ".local" / "bin" / "configtest").is_symlink()


# ---------------------------------------------------------------------------
# Test 6: permissions.deny entries are collected and written to settings.json
# ---------------------------------------------------------------------------


def test_permissions_deny_entry_written(mini_repo, config_dir, run_deploy):
    """permissions.deny entries from deploy.json are written to settings.json."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={
            "permissions": {
                "allow": ["Bash(configtest)"],
                "deny": ["Bash(rm -rf *)"],
            }
        },
    )

    run_deploy()

    settings = json.loads((config_dir / "settings.json").read_text())
    assert "Bash(rm -rf *)" in settings["permissions"]["deny"]


def test_permissions_allow_entry_written_alongside_deny(mini_repo, config_dir, run_deploy):
    """permissions.allow entries are also written when deny is present."""
    mini_repo.create_skill(
        "configtest",
        md_content=MD_CONTENT,
        deploy_json={
            "permissions": {
                "allow": ["Bash(configtest)"],
                "deny": ["Bash(rm -rf *)"],
            }
        },
    )

    run_deploy()

    settings = json.loads((config_dir / "settings.json").read_text())
    assert "Bash(configtest)" in settings["permissions"]["allow"]


# ---------------------------------------------------------------------------
# Test 7: repo-root deploy.local.json overrides repo-root deploy.json
# ---------------------------------------------------------------------------


def test_repo_root_deploy_local_json_overrides_deploy_json(
    mini_repo, config_dir, run_deploy, tmp_path
):
    """Repo-root deploy.local.json on_path: false wins over deploy.json on_path: true."""
    mini_repo.create_skill("configtest", md_content=MD_CONTENT)
    mini_repo.create_deploy_json({"on_path": True})
    mini_repo.create_deploy_local_json({"on_path": False})

    fake_home = tmp_path / "fake_home"
    fake_home.mkdir()

    run_deploy(
        "--skip-permissions",
        env_overrides={"HOME": str(fake_home)},
    )

    assert not (fake_home / ".local" / "bin" / "configtest").is_symlink()
