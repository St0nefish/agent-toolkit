"""Tests for permission group deployment.

Covers:
  1. Permission group contributes allow entries to settings.json
  2. Disabled group skipped, permissions not included
  3. --include / --exclude filter permission groups
  4. Profile enables/disables permission groups
  5. Profile drift: group in profile but not on disk → stale warning
  6. No permissions/ dir → backward compatible (no errors)
  7. .local.json overlay merges on top of base file
  8. Idempotency: deploy twice → settings.json unchanged
  9. --discover includes "permissions" in output
  10. Grouped sort: verify permissions in settings.json are grouped by category
"""

import json

import pytest


SEED_SETTINGS = {
    "env": {"TEST": "preserved"},
    "model": "test-model",
}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_with_groups(mini_repo):
    """Mini-repo with two permission groups and a skill."""
    mini_repo.create_skill(
        "basic-tool",
        md_content="---\ndescription: Basic tool\n---\n# basic-tool\n",
    )
    mini_repo.create_permission_group(
        "git",
        permissions={"allow": ["Bash(git status)", "Bash(git log)"]},
    )
    mini_repo.create_permission_group(
        "docker",
        permissions={"allow": ["Bash(docker ps)", "Bash(docker images)"]},
    )
    return mini_repo


@pytest.fixture
def seeded_settings(config_dir):
    settings_path = config_dir / "settings.json"
    settings_path.write_text(json.dumps(SEED_SETTINGS, indent=2) + "\n")
    return config_dir


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------


def read_settings(config_dir):
    return json.loads((config_dir / "settings.json").read_text())


# ---------------------------------------------------------------------------
# Test 1: Permission group contributes allow entries
# ---------------------------------------------------------------------------


class TestPermissionGroupContributes:
    @pytest.fixture(autouse=True)
    def _deploy(self, repo_with_groups, seeded_settings, run_deploy):
        self.result = run_deploy(config_dir=seeded_settings)
        self.settings = read_settings(seeded_settings)

    def test_output_mentions_permissions_section(self):
        combined = self.result.stdout + self.result.stderr
        assert "=== Permissions ===" in combined

    def test_git_permissions_present(self):
        allow = self.settings["permissions"]["allow"]
        assert "Bash(git status)" in allow
        assert "Bash(git log)" in allow

    def test_docker_permissions_present(self):
        allow = self.settings["permissions"]["allow"]
        assert "Bash(docker ps)" in allow
        assert "Bash(docker images)" in allow

    def test_output_shows_included_groups(self):
        combined = self.result.stdout + self.result.stderr
        assert "Included: git" in combined
        assert "Included: docker" in combined


# ---------------------------------------------------------------------------
# Test 2: Disabled group skipped
# ---------------------------------------------------------------------------


def test_disabled_group_skipped(mini_repo, seeded_settings, run_deploy):
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    mini_repo.create_permission_group(
        "disabled-group",
        permissions={"allow": ["Bash(secret-tool)"]},
        deploy_overrides={"enabled": False},
    )

    run_deploy(config_dir=seeded_settings)
    settings = read_settings(seeded_settings)
    allow = settings.get("permissions", {}).get("allow", [])
    assert "Bash(secret-tool)" not in allow


# ---------------------------------------------------------------------------
# Test 3: --include / --exclude filter permission groups
# ---------------------------------------------------------------------------


class TestFilterPermissionGroups:
    def test_include_only_git(self, repo_with_groups, seeded_settings, run_deploy):
        run_deploy("--include", "git", config_dir=seeded_settings)
        settings = read_settings(seeded_settings)
        allow = settings.get("permissions", {}).get("allow", [])
        assert "Bash(git status)" in allow
        assert "Bash(docker ps)" not in allow

    def test_exclude_docker(self, repo_with_groups, seeded_settings, run_deploy):
        run_deploy("--exclude", "docker", config_dir=seeded_settings)
        settings = read_settings(seeded_settings)
        allow = settings.get("permissions", {}).get("allow", [])
        assert "Bash(git status)" in allow
        assert "Bash(docker ps)" not in allow


# ---------------------------------------------------------------------------
# Test 4: Profile enables/disables permission groups
# ---------------------------------------------------------------------------


def test_profile_disables_group(mini_repo, seeded_settings, run_deploy):
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    mini_repo.create_permission_group(
        "git",
        permissions={"allow": ["Bash(git status)"]},
    )
    mini_repo.create_permission_group(
        "docker",
        permissions={"allow": ["Bash(docker ps)"]},
    )

    profile_path = mini_repo.root / "test-profile.json"
    profile_path.write_text(json.dumps({
        "skills": {"basic-tool": {"enabled": True}},
        "permissions": {
            "git": {"enabled": True},
            "docker": {"enabled": False},
        },
    }, indent=2) + "\n")

    run_deploy("--profile", str(profile_path), config_dir=seeded_settings)
    settings = read_settings(seeded_settings)
    allow = settings.get("permissions", {}).get("allow", [])
    assert "Bash(git status)" in allow
    assert "Bash(docker ps)" not in allow


# ---------------------------------------------------------------------------
# Test 5: Profile drift — stale permission group
# ---------------------------------------------------------------------------


def test_profile_drift_stale_permission(mini_repo, seeded_settings, run_deploy):
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    mini_repo.create_permission_group(
        "git",
        permissions={"allow": ["Bash(git status)"]},
    )

    profile_path = mini_repo.root / "test-profile.json"
    profile_path.write_text(json.dumps({
        "skills": {"basic-tool": {"enabled": True}},
        "permissions": {
            "git": {"enabled": True},
            "nonexistent": {"enabled": True},
        },
    }, indent=2) + "\n")

    result = run_deploy("--profile", str(profile_path), config_dir=seeded_settings)
    combined = result.stdout + result.stderr
    assert "nonexistent (permissions)" in combined


# ---------------------------------------------------------------------------
# Test 6: No permissions/ dir → backward compatible
# ---------------------------------------------------------------------------


def test_no_permissions_dir_is_fine(mini_repo, seeded_settings, run_deploy):
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    # No permissions dir created
    result = run_deploy(config_dir=seeded_settings)
    assert result.returncode == 0
    combined = result.stdout + result.stderr
    assert "=== Permissions ===" not in combined


# ---------------------------------------------------------------------------
# Test 7: .local.json overlay merges on top of base
# ---------------------------------------------------------------------------


def test_local_json_overlay(mini_repo, seeded_settings, run_deploy):
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    mini_repo.create_permission_group(
        "git",
        permissions={"allow": ["Bash(git status)"]},
    )
    mini_repo.create_permission_group_local(
        "git",
        {"permissions": {"allow": ["Bash(git log)", "Bash(git diff)"]}},
    )

    run_deploy(config_dir=seeded_settings)
    settings = read_settings(seeded_settings)
    allow = settings.get("permissions", {}).get("allow", [])
    # Both base and local entries should be present
    assert "Bash(git status)" in allow
    assert "Bash(git log)" in allow
    assert "Bash(git diff)" in allow


# ---------------------------------------------------------------------------
# Test 8: Idempotency
# ---------------------------------------------------------------------------


def test_idempotency(repo_with_groups, seeded_settings, run_deploy):
    run_deploy(config_dir=seeded_settings)
    after_first = (seeded_settings / "settings.json").read_text()

    run_deploy(config_dir=seeded_settings)
    after_second = (seeded_settings / "settings.json").read_text()

    assert after_first == after_second


# ---------------------------------------------------------------------------
# Test 9: --discover includes permissions
# ---------------------------------------------------------------------------


def test_discover_includes_permissions(repo_with_groups, run_deploy):
    result = run_deploy("--discover")
    data = json.loads(result.stdout)
    assert "permissions" in data
    names = [p["name"] for p in data["permissions"]]
    assert "git" in names
    assert "docker" in names


# ---------------------------------------------------------------------------
# Test 10: Grouped sort
# ---------------------------------------------------------------------------


def test_grouped_sort(mini_repo, seeded_settings, run_deploy):
    """Permissions should be grouped: git entries before docker entries."""
    mini_repo.create_skill("basic-tool", md_content="# basic\n")
    mini_repo.create_permission_group(
        "docker",
        permissions={"allow": ["Bash(docker ps)"]},
    )
    mini_repo.create_permission_group(
        "git",
        permissions={"allow": ["Bash(git status)"]},
    )

    run_deploy(config_dir=seeded_settings)
    settings = read_settings(seeded_settings)
    allow = settings["permissions"]["allow"]

    git_idx = allow.index("Bash(git status)")
    docker_idx = allow.index("Bash(docker ps)")
    # git (03-git) should come before docker (04-docker) in grouped sort
    assert git_idx < docker_idx
