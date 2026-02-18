"""Tests for deploy.py CLI argument validation.

Port of tests/test-deploy-cli-validation.sh.
"""

import pytest


@pytest.fixture(autouse=True)
def setup_alpha(mini_repo):
    """Create a minimal 'alpha' skill in the mini-repo for all tests."""
    mini_repo.create_skill(
        "alpha",
        md_content="---\ndescription: Test tool alpha\n---\n# Alpha\n",
    )


def test_include_and_exclude_are_mutually_exclusive(run_deploy):
    """--include and --exclude together must exit 1 with a 'mutually exclusive' message."""
    result = run_deploy("--include", "alpha", "--exclude", "alpha")
    output = result.stdout + result.stderr

    assert result.returncode == 1
    assert "mutually exclusive" in output.lower()


def test_project_and_on_path_are_incompatible(run_deploy, tmp_path):
    """--project and --on-path together must exit 1 with a 'not supported' message."""
    project_dir = tmp_path / "project"
    project_dir.mkdir()

    result = run_deploy("--project", str(project_dir), "--on-path")
    output = result.stdout + result.stderr

    assert result.returncode == 1
    assert "not supported" in output.lower()


def test_project_with_nonexistent_path(run_deploy):
    """--project with a path that does not exist must exit 1 with a 'does not exist' message."""
    result = run_deploy("--project", "/nonexistent/path/that/does/not/exist")
    output = result.stdout + result.stderr

    assert result.returncode == 1
    assert "does not exist" in output.lower()


def test_unknown_flag(run_deploy):
    """An unrecognised flag must exit non-zero with an 'unknown option' message."""
    result = run_deploy("--bogus-flag")
    output = result.stdout + result.stderr

    assert result.returncode in (1, 2)
    assert "unrecognized arguments" in output.lower()
