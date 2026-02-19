"""Tests for deploy.py dependency support.

Port of tests/test-deploy-dependencies.sh. Uses synthetic tools rather than
real repo catchup/session skills so tests are self-contained and hermetic.
"""

import hashlib
import json


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def md5_file(path):
    """Return hex MD5 digest of the file at *path*."""
    return hashlib.md5(path.read_bytes()).hexdigest()


def read_settings(config_dir):
    """Parse and return settings.json from config_dir."""
    return json.loads((config_dir / "settings.json").read_text())


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


import pytest


@pytest.fixture
def repo(mini_repo):
    """Mini-repo with main-tool (depends on dep-tool) and orphan-tool."""
    mini_repo.create_skill(
        "main-tool",
        md_content="---\ndescription: Main tool\n---\n# Main Tool\n",
        deploy_json={
            "dependencies": ["dep-tool"],
            "permissions": {"allow": ["Bash(main-tool)"]},
        },
    )
    mini_repo.create_skill(
        "dep-tool",
        md_content="---\ndescription: Dep tool\n---\n# Dep Tool\n",
        deploy_json={
            "permissions": {"allow": ["Bash(dep-tool)", "Bash(dep-tool *)"]},
        },
    )
    return mini_repo


# ---------------------------------------------------------------------------
# Test: dependency tool dir is symlinked
# ---------------------------------------------------------------------------


class TestDependencyToolDirSymlinked:
    def test_dep_tool_dir_symlinked(self, repo, config_dir, run_deploy):
        """Deploying only main-tool causes dep-tool's tool dir to be symlinked."""
        run_deploy("--no-profile", "--include", "main-tool")
        assert (config_dir / "tools" / "dep-tool").is_symlink()

    def test_main_tool_dir_symlinked(self, repo, config_dir, run_deploy):
        """main-tool itself is symlinked into tools/."""
        run_deploy("--no-profile", "--include", "main-tool")
        assert (config_dir / "tools" / "main-tool").is_symlink()


# ---------------------------------------------------------------------------
# Test: dependency permissions collected
# ---------------------------------------------------------------------------


class TestDependencyPermissionsCollected:
    def test_dep_tool_permission_collected(self, repo, config_dir, run_deploy):
        """dep-tool's Bash(dep-tool) permission appears in settings.json."""
        run_deploy("--no-profile", "--include", "main-tool")
        settings = read_settings(config_dir)
        assert "Bash(dep-tool)" in settings["permissions"]["allow"]

    def test_dep_tool_wildcard_permission_collected(self, repo, config_dir, run_deploy):
        """dep-tool's Bash(dep-tool *) wildcard permission appears in settings.json."""
        run_deploy("--no-profile", "--include", "main-tool")
        settings = read_settings(config_dir)
        assert "Bash(dep-tool *)" in settings["permissions"]["allow"]


# ---------------------------------------------------------------------------
# Test: dependency skills NOT deployed
# ---------------------------------------------------------------------------


class TestDependencySkillsNotDeployed:
    def test_dep_tool_skill_not_deployed(self, repo, config_dir, run_deploy):
        """dep-tool's .md skill is NOT deployed when it is only a dependency."""
        run_deploy("--no-profile", "--include", "main-tool")
        assert not (config_dir / "skills" / "dep-tool" / "SKILL.md").exists()

    def test_main_tool_skill_is_deployed(self, repo, config_dir, run_deploy):
        """main-tool's own .md skill IS deployed."""
        run_deploy("--no-profile", "--include", "main-tool")
        assert (config_dir / "skills" / "main-tool" / "SKILL.md").is_symlink()


# ---------------------------------------------------------------------------
# Test: output mentions dependency linking
# ---------------------------------------------------------------------------


def test_output_mentions_dependency_linking(repo, config_dir, run_deploy):
    """Deploy output contains 'dependency of main-tool' to describe dep linking."""
    result = run_deploy("--no-profile", "--include", "main-tool")
    combined = result.stdout + result.stderr
    assert "dependency of main-tool" in combined


# ---------------------------------------------------------------------------
# Test: deploying dep-tool directly works standalone
# ---------------------------------------------------------------------------


def test_deploying_dep_tool_directly(repo, config_dir, run_deploy, tmp_path):
    """dep-tool can be deployed on its own: tool dir symlinked and skill deployed."""
    cfg2 = tmp_path / "cfg2"
    cfg2.mkdir()

    run_deploy("--no-profile", "--include", "dep-tool", config_dir=cfg2)

    assert (cfg2 / "tools" / "dep-tool").is_symlink()
    assert (cfg2 / "skills" / "dep-tool" / "SKILL.md").is_symlink()


# ---------------------------------------------------------------------------
# Test: missing dependency warns but doesn't fail
# ---------------------------------------------------------------------------


class TestMissingDependency:
    @pytest.fixture
    def repo_with_orphan(self, mini_repo):
        mini_repo.create_skill(
            "orphan-tool",
            md_content="---\ndescription: Orphan tool\n---\n# Orphan Tool\n",
            deploy_json={"dependencies": ["nonexistent-tool"]},
        )
        return mini_repo

    def test_missing_dependency_warns(self, repo_with_orphan, config_dir, run_deploy):
        """A missing dependency emits a warning."""
        result = run_deploy("--no-profile")
        combined = result.stdout + result.stderr
        assert "Warning: dependency 'nonexistent-tool' not found" in combined

    def test_deploy_continues_after_missing_dependency(
        self, repo_with_orphan, config_dir, run_deploy
    ):
        """Deploy doesn't fail and still deploys the tool with a missing dependency."""
        result = run_deploy("--no-profile")
        combined = result.stdout + result.stderr
        assert "Deployed: orphan-tool" in combined


# ---------------------------------------------------------------------------
# Test: idempotency
# ---------------------------------------------------------------------------


class TestIdempotency:
    def test_settings_json_unchanged_on_redeploy(self, repo, config_dir, run_deploy):
        """Running deploy twice leaves settings.json byte-for-byte identical."""
        run_deploy("--no-profile", "--include", "main-tool")
        md5_before = md5_file(config_dir / "settings.json")

        run_deploy("--no-profile", "--include", "main-tool")
        md5_after = md5_file(config_dir / "settings.json")

        assert md5_before == md5_after

    def test_dep_tool_symlink_survives_redeploy(self, repo, config_dir, run_deploy):
        """dep-tool symlink is still present after a second deploy run."""
        run_deploy("--no-profile", "--include", "main-tool")
        run_deploy("--no-profile", "--include", "main-tool")

        assert (config_dir / "tools" / "dep-tool").is_symlink()
