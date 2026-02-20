"""Tests for deploy.py permission management.

Port of tests/test-deploy-permissions.sh. Covers:
  1. Dry-run + --skip-permissions: settings.json is not modified
  2. Actual deploy writes permissions from skill and repo-level deploy.json
  3. Idempotency: running deploy twice leaves settings.json unchanged
  4. Append-missing semantics: manually added entries survive re-deployment
  5. --skip-permissions: outputs skip message, does not touch settings.json
  6. Project-scoped tools: permissions excluded from global deploy
"""

import json

import pytest


SEED_SETTINGS = {
    "env": {"TEST": "preserved"},
    "model": "test-model",
    "hooks": {"PreToolUse": []},
}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def repo(mini_repo):
    """Mini-repo with a skill that declares permissions and a repo-level config."""
    mini_repo.create_skill(
        "perm-tool",
        md_content="---\ndescription: Permission test tool\n---\n# perm-tool\n",
        deploy_json={
            "permissions": {
                "allow": ["Bash(find)", "Bash(ls *)"],
                "deny": [],
            }
        },
    )
    mini_repo.create_deploy_json(
        {
            "permissions": {
                "allow": ["Bash(git status)", "Bash(git log)", "Bash(git diff)"],
            }
        }
    )
    return mini_repo


@pytest.fixture
def seeded_settings(config_dir):
    """Write the standard seed settings.json and return config_dir."""
    settings_path = config_dir / "settings.json"
    settings_path.write_text(json.dumps(SEED_SETTINGS, indent=2) + "\n")
    return config_dir


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------


def read_settings(config_dir):
    return json.loads((config_dir / "settings.json").read_text())


# ---------------------------------------------------------------------------
# Test 1: dry-run + --skip-permissions leaves settings.json untouched
# ---------------------------------------------------------------------------


class TestDryRunSkipPermissions:
    def test_no_tmp_file_created(self, repo, seeded_settings, run_deploy):
        run_deploy("--no-profile", "--dry-run", "--skip-permissions")
        assert not (seeded_settings / "settings.json.tmp").exists()

    def test_settings_json_unchanged(self, repo, seeded_settings, run_deploy):
        original = (seeded_settings / "settings.json").read_text()
        run_deploy("--no-profile", "--dry-run", "--skip-permissions")
        after = (seeded_settings / "settings.json").read_text()
        assert after == original


# ---------------------------------------------------------------------------
# Test 2: actual deploy writes permissions
# ---------------------------------------------------------------------------


class TestActualDeployWritesPermissions:
    @pytest.fixture(autouse=True)
    def _deploy_once(self, repo, seeded_settings, run_deploy):
        self.result = run_deploy("--no-profile", config_dir=seeded_settings)
        self.settings = read_settings(seeded_settings)

    def test_output_mentions_updated_with_allow_entries(self):
        combined = self.result.stdout + self.result.stderr
        assert "Updated:" in combined
        assert "permissions" in combined
        assert "allow entries" in combined

    def test_permissions_allow_is_array(self):
        assert isinstance(self.settings.get("permissions", {}).get("allow"), list)

    def test_contains_bash_find(self):
        assert "Bash(find)" in self.settings["permissions"]["allow"]

    def test_contains_bash_ls_star(self):
        assert "Bash(ls *)" in self.settings["permissions"]["allow"]

    def test_contains_bash_git_status(self):
        assert "Bash(git status)" in self.settings["permissions"]["allow"]

    def test_contains_bash_git_log(self):
        assert "Bash(git log)" in self.settings["permissions"]["allow"]

    def test_contains_bash_git_diff(self):
        assert "Bash(git diff)" in self.settings["permissions"]["allow"]

    def test_env_test_preserved(self):
        assert self.settings.get("env", {}).get("TEST") == "preserved"

    def test_model_preserved(self):
        assert self.settings.get("model") == "test-model"

    def test_hooks_key_is_object(self):
        assert isinstance(self.settings.get("hooks"), dict)

    def test_permissions_deny_is_empty_array(self):
        assert self.settings.get("permissions", {}).get("deny") == []

    def test_allow_array_is_grouped_sorted(self):
        """Permissions are sorted by group then alphabetically within group."""
        from deploy.permissions import _permission_sort_key
        allow = self.settings["permissions"]["allow"]
        assert allow == sorted(allow, key=_permission_sort_key)


# ---------------------------------------------------------------------------
# Test 3: idempotency
# ---------------------------------------------------------------------------


def test_idempotency(repo, seeded_settings, run_deploy):
    """Running deploy twice must leave settings.json identical."""
    run_deploy("--no-profile", config_dir=seeded_settings)
    after_first = (seeded_settings / "settings.json").read_text()

    run_deploy("--no-profile", config_dir=seeded_settings)
    after_second = (seeded_settings / "settings.json").read_text()

    assert after_first == after_second


# ---------------------------------------------------------------------------
# Test 4: append-missing preserves manual entries
# ---------------------------------------------------------------------------


class TestAppendMissingPreservesManualEntries:
    def test_custom_entry_survives_redeploy(self, repo, seeded_settings, run_deploy):
        """A manually added allow entry must survive a re-deployment."""
        # First deploy to establish baseline permissions
        run_deploy("--no-profile", config_dir=seeded_settings)

        # Inject a custom permission entry
        settings_path = seeded_settings / "settings.json"
        data = json.loads(settings_path.read_text())
        data["permissions"]["allow"].append("Bash(my-custom-tool *)")
        settings_path.write_text(json.dumps(data, indent=2) + "\n")

        # Re-deploy — custom entry should survive
        run_deploy("--no-profile", config_dir=seeded_settings)

        after = read_settings(seeded_settings)
        assert "Bash(my-custom-tool *)" in after["permissions"]["allow"]

    def test_deployed_entries_still_present_after_append(self, repo, seeded_settings, run_deploy):
        """Original deployed entries are still present after the re-deployment."""
        run_deploy("--no-profile", config_dir=seeded_settings)

        settings_path = seeded_settings / "settings.json"
        data = json.loads(settings_path.read_text())
        data["permissions"]["allow"].append("Bash(my-custom-tool *)")
        settings_path.write_text(json.dumps(data, indent=2) + "\n")

        run_deploy("--no-profile", config_dir=seeded_settings)

        after = read_settings(seeded_settings)
        assert "Bash(find)" in after["permissions"]["allow"]


# ---------------------------------------------------------------------------
# Test 5: --skip-permissions
# ---------------------------------------------------------------------------


def test_skip_permissions_message(repo, seeded_settings, run_deploy):
    """--skip-permissions must print the skip message."""
    result = run_deploy("--no-profile", "--skip-permissions", config_dir=seeded_settings)
    combined = result.stdout + result.stderr
    assert "Skipped: permissions management" in combined


# ---------------------------------------------------------------------------
# Test 6: project-scoped tools excluded from global deploy
# ---------------------------------------------------------------------------


def test_project_scoped_tool_permissions_not_in_global_deploy(mini_repo, config_dir, run_deploy):
    """A project-scoped tool's permissions must not appear in global settings.json."""
    settings_path = config_dir / "settings.json"
    settings_path.write_text(json.dumps(SEED_SETTINGS, indent=2) + "\n")

    mini_repo.create_skill(
        "project-tool",
        md_content="---\ndescription: Project-only tool\n---\n# project-tool\n",
        deploy_json={
            "scope": "project",
            "permissions": {
                "allow": ["Bash(project-only)"],
            },
        },
    )

    run_deploy("--no-profile", config_dir=config_dir)

    settings = read_settings(config_dir)
    allow = settings.get("permissions", {}).get("allow", [])
    assert "Bash(project-only)" not in allow
