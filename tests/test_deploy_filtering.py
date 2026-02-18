"""Tests for deploy.py --include, --exclude, condition.sh, and enabled config.

Port of tests/test-deploy-filtering.sh.
"""

import pytest


def make_skill(mini_repo, name, **kwargs):
    """Create a standard test skill with frontmatter md_content."""
    kwargs.setdefault("md_content", f"---\ndescription: Test tool {name}\n---\n# {name}")
    return mini_repo.create_skill(name, **kwargs)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_with_three_skills(mini_repo):
    """Mini repo with alpha, beta, gamma skills pre-created."""
    make_skill(mini_repo, "alpha")
    make_skill(mini_repo, "beta")
    make_skill(mini_repo, "gamma")
    return mini_repo


# ---------------------------------------------------------------------------
# --include
# ---------------------------------------------------------------------------


class TestInclude:
    def test_included_tool_is_deployed(self, repo_with_three_skills, config_dir, run_deploy):
        run_deploy("--include", "alpha", "--skip-permissions")
        assert (config_dir / "tools" / "alpha").is_symlink()

    def test_excluded_tools_are_not_deployed(self, repo_with_three_skills, config_dir, run_deploy):
        run_deploy("--include", "alpha", "--skip-permissions")
        assert not (config_dir / "tools" / "beta").exists()
        assert not (config_dir / "tools" / "gamma").exists()

    def test_filtered_tools_emit_message(self, repo_with_three_skills, config_dir, run_deploy):
        result = run_deploy("--include", "alpha", "--skip-permissions")
        assert "Skipped: beta (filtered out)" in result.stdout
        assert "Skipped: gamma (filtered out)" in result.stdout


# ---------------------------------------------------------------------------
# --exclude
# ---------------------------------------------------------------------------


class TestExclude:
    def test_non_excluded_tools_are_deployed(self, repo_with_three_skills, config_dir, run_deploy):
        run_deploy("--exclude", "beta", "--skip-permissions")
        assert (config_dir / "tools" / "alpha").is_symlink()
        assert (config_dir / "tools" / "gamma").is_symlink()

    def test_excluded_tool_is_not_deployed(self, repo_with_three_skills, config_dir, run_deploy):
        run_deploy("--exclude", "beta", "--skip-permissions")
        assert not (config_dir / "tools" / "beta").exists()

    def test_excluded_tool_emits_filtered_message(self, repo_with_three_skills, config_dir, run_deploy):
        result = run_deploy("--exclude", "beta", "--skip-permissions")
        assert "Skipped: beta (filtered out)" in result.stdout


# ---------------------------------------------------------------------------
# condition.sh
# ---------------------------------------------------------------------------


class TestConditionSh:
    def test_failing_condition_skips_tool(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta", condition_sh="#!/usr/bin/env bash\nexit 1")
        make_skill(mini_repo, "gamma")

        run_deploy("--skip-permissions")

        assert not (config_dir / "tools" / "beta").exists()

    def test_failing_condition_emits_message(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta", condition_sh="#!/usr/bin/env bash\nexit 1")
        make_skill(mini_repo, "gamma")

        result = run_deploy("--skip-permissions")

        assert "Skipped: beta (condition not met)" in result.stdout

    def test_failing_condition_does_not_affect_other_tools(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta", condition_sh="#!/usr/bin/env bash\nexit 1")
        make_skill(mini_repo, "gamma")

        run_deploy("--skip-permissions")

        assert (config_dir / "tools" / "alpha").is_symlink()

    def test_passing_condition_deploys_tool(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta", condition_sh="#!/usr/bin/env bash\nexit 0")
        make_skill(mini_repo, "gamma")

        run_deploy("--skip-permissions")

        assert (config_dir / "tools" / "beta").is_symlink()


# ---------------------------------------------------------------------------
# enabled: false
# ---------------------------------------------------------------------------


class TestEnabledFalse:
    def test_disabled_tool_is_not_deployed(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta")
        make_skill(mini_repo, "gamma", deploy_json={"enabled": False})

        run_deploy("--skip-permissions")

        assert not (config_dir / "tools" / "gamma").exists()

    def test_disabled_tool_emits_message(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta")
        make_skill(mini_repo, "gamma", deploy_json={"enabled": False})

        result = run_deploy("--skip-permissions")

        assert "Skipped: gamma (disabled by config)" in result.stdout

    def test_disabled_tool_does_not_affect_others(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo, "alpha")
        make_skill(mini_repo, "beta")
        make_skill(mini_repo, "gamma", deploy_json={"enabled": False})

        run_deploy("--skip-permissions")

        assert (config_dir / "tools" / "alpha").is_symlink()


# ---------------------------------------------------------------------------
# Hook filtering
# ---------------------------------------------------------------------------


class TestHookFiltering:
    def test_exclude_filters_hook(self, repo_with_three_skills, mini_repo, config_dir, run_deploy):
        mini_repo.create_hook("test-hook")

        result = run_deploy("--exclude", "test-hook", "--skip-permissions")

        assert "Skipped: hook test-hook (filtered out)" in result.stdout

    def test_excluded_hook_is_not_symlinked(self, repo_with_three_skills, mini_repo, config_dir, run_deploy):
        mini_repo.create_hook("test-hook")

        run_deploy("--exclude", "test-hook", "--skip-permissions")

        assert not (config_dir / "hooks" / "test-hook").exists()

    def test_hook_deployed_without_exclude(self, repo_with_three_skills, mini_repo, config_dir, run_deploy):
        mini_repo.create_hook("test-hook")

        run_deploy("--skip-permissions")

        assert (config_dir / "hooks" / "test-hook").is_symlink()
