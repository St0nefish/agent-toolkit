"""Tests for MCP server deployment via deploy.py.

Tests cover:
- deploy_mcp with valid config, missing mcp key, filtered, disabled
- setup.sh success and failure paths
- update_settings_mcp append-missing (global + project .mcp.json)
- remove_settings_mcp
- teardown_mcp
- CLI --teardown-mcp parsing
"""

import json

import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_skill(mini_repo, name="dummy"):
    """Create a dummy skill so deploy.py doesn't early-return when skills/ is missing."""
    mini_repo.create_skill(
        name,
        md_content=f"---\ndescription: dummy skill\n---\n# {name}\n",
    )


def read_settings(config_dir):
    return json.loads((config_dir / "settings.json").read_text())


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_with_mcp(mini_repo):
    """Mini repo with a dummy skill and an MCP server."""
    make_skill(mini_repo)
    mini_repo.create_mcp(
        "test-mcp",
        deploy_json={
            "mcp": {
                "command": "docker",
                "args": ["run", "--rm", "-i", "test-image:latest"],
                "env": {},
            }
        },
    )
    return mini_repo


@pytest.fixture
def repo_with_mcp_and_setup(mini_repo):
    """Mini repo with MCP server that has a setup.sh."""
    make_skill(mini_repo)
    mini_repo.create_mcp(
        "test-mcp",
        deploy_json={
            "mcp": {
                "command": "docker",
                "args": ["run", "--rm", "-i", "test-image:latest"],
                "env": {},
            }
        },
        setup_sh="#!/usr/bin/env bash\necho 'setup ok'\n",
    )
    return mini_repo


@pytest.fixture
def seeded_settings(config_dir):
    """Seed settings.json with extra keys to verify they are preserved."""
    settings = {"env": {"TEST": "preserved"}, "model": "test-model"}
    (config_dir / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
    return config_dir


# ---------------------------------------------------------------------------
# Test: MCP deployment with valid config
# ---------------------------------------------------------------------------


class TestMcpValidConfig:
    def test_mcp_section_in_output(self, repo_with_mcp, config_dir, run_deploy):
        result = run_deploy("--no-profile")
        assert "=== MCP ===" in result.stdout

    def test_mcp_deployed_message(self, repo_with_mcp, config_dir, run_deploy):
        result = run_deploy("--no-profile")
        assert "Deployed: test-mcp" in result.stdout

    def test_mcp_registered_in_settings(self, repo_with_mcp, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert "test-mcp" in settings.get("mcpServers", {})

    def test_mcp_server_def_correct(self, repo_with_mcp, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        server = settings["mcpServers"]["test-mcp"]
        assert server["command"] == "docker"
        assert server["args"] == ["run", "--rm", "-i", "test-image:latest"]

    def test_mcp_preserves_other_settings(self, repo_with_mcp, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert settings.get("env", {}).get("TEST") == "preserved"


# ---------------------------------------------------------------------------
# Test: MCP with missing mcp key
# ---------------------------------------------------------------------------


class TestMcpMissingKey:
    def test_missing_mcp_key_skips(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo)
        mini_repo.create_mcp("bad-mcp", deploy_json={"enabled": True})

        result = run_deploy("--no-profile")
        assert "missing or invalid 'mcp' key" in result.stdout

    def test_missing_mcp_key_not_registered(self, mini_repo, seeded_settings, run_deploy):
        make_skill(mini_repo)
        mini_repo.create_mcp("bad-mcp", deploy_json={"enabled": True})

        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert "bad-mcp" not in settings.get("mcpServers", {})


# ---------------------------------------------------------------------------
# Test: MCP filtered by --include/--exclude
# ---------------------------------------------------------------------------


class TestMcpFiltering:
    def test_exclude_filters_mcp(self, repo_with_mcp, config_dir, run_deploy):
        result = run_deploy("--exclude", "test-mcp", "--no-profile")
        assert "Skipped: test-mcp (filtered out)" in result.stdout

    def test_include_other_skips_mcp(self, repo_with_mcp, config_dir, run_deploy):
        result = run_deploy("--include", "dummy", "--no-profile")
        assert "Skipped: test-mcp (filtered out)" in result.stdout

    def test_include_mcp_deploys_it(self, repo_with_mcp, seeded_settings, run_deploy):
        run_deploy("--include", "test-mcp", "dummy", "--no-profile")
        settings = read_settings(seeded_settings)
        assert "test-mcp" in settings.get("mcpServers", {})


# ---------------------------------------------------------------------------
# Test: MCP disabled by config
# ---------------------------------------------------------------------------


class TestMcpDisabled:
    def test_disabled_mcp_skips(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo)
        mini_repo.create_mcp(
            "disabled-mcp",
            deploy_json={
                "enabled": False,
                "mcp": {
                    "command": "docker",
                    "args": ["run", "test"],
                },
            },
        )

        result = run_deploy("--no-profile")
        assert "Skipped: disabled-mcp (disabled by config)" in result.stdout


# ---------------------------------------------------------------------------
# Test: setup.sh success
# ---------------------------------------------------------------------------


class TestSetupShSuccess:
    def test_setup_runs_on_deploy(self, repo_with_mcp_and_setup, config_dir, run_deploy):
        result = run_deploy("--no-profile")
        assert "setup ok" in result.stdout

    def test_setup_still_registers(self, repo_with_mcp_and_setup, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert "test-mcp" in settings.get("mcpServers", {})


# ---------------------------------------------------------------------------
# Test: setup.sh failure
# ---------------------------------------------------------------------------


class TestSetupShFailure:
    def test_failing_setup_warns(self, mini_repo, config_dir, run_deploy):
        make_skill(mini_repo)
        mini_repo.create_mcp(
            "fail-mcp",
            deploy_json={
                "mcp": {
                    "command": "docker",
                    "args": ["run", "test"],
                },
            },
            setup_sh="#!/usr/bin/env bash\necho 'failing' >&2\nexit 1\n",
        )

        result = run_deploy("--no-profile")
        assert "setup.sh failed" in result.stdout

    def test_failing_setup_not_registered(self, mini_repo, seeded_settings, run_deploy):
        make_skill(mini_repo)
        mini_repo.create_mcp(
            "fail-mcp",
            deploy_json={
                "mcp": {
                    "command": "docker",
                    "args": ["run", "test"],
                },
            },
            setup_sh="#!/usr/bin/env bash\nexit 1\n",
        )

        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert "fail-mcp" not in settings.get("mcpServers", {})


# ---------------------------------------------------------------------------
# Test: append-missing semantics
# ---------------------------------------------------------------------------


class TestAppendMissing:
    def test_existing_server_preserved(self, repo_with_mcp, seeded_settings, run_deploy):
        """A manually added MCP server must survive re-deploy."""
        # First deploy
        run_deploy("--no-profile")

        # Inject a manual server
        settings = read_settings(seeded_settings)
        settings.setdefault("mcpServers", {})["manual-server"] = {
            "command": "npx", "args": ["manual"]
        }
        (seeded_settings / "settings.json").write_text(
            json.dumps(settings, indent=2) + "\n"
        )

        # Re-deploy
        run_deploy("--no-profile")

        settings_after = read_settings(seeded_settings)
        assert "manual-server" in settings_after.get("mcpServers", {})
        assert "test-mcp" in settings_after.get("mcpServers", {})

    def test_idempotent(self, repo_with_mcp, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        first = (seeded_settings / "settings.json").read_text()

        run_deploy("--no-profile")
        second = (seeded_settings / "settings.json").read_text()

        assert first == second


# ---------------------------------------------------------------------------
# Test: project scope writes to .mcp.json
# ---------------------------------------------------------------------------


class TestProjectMcp:
    def test_project_writes_mcp_json(self, repo_with_mcp, config_dir, run_deploy, tmp_path):
        project_dir = tmp_path / "my_project"
        project_dir.mkdir()

        run_deploy("--project", str(project_dir), "--no-profile")

        mcp_json = project_dir / ".mcp.json"
        assert mcp_json.exists()
        data = json.loads(mcp_json.read_text())
        assert "test-mcp" in data.get("mcpServers", {})


# ---------------------------------------------------------------------------
# Test: --teardown-mcp CLI parsing
# ---------------------------------------------------------------------------


class TestTeardownMcpCli:
    def test_teardown_mcp_requires_name(self, mini_repo, config_dir, run_deploy):
        result = run_deploy("--teardown-mcp")
        assert result.returncode != 0
        assert "requires at least one NAME" in result.stderr

    def test_teardown_mcp_removes_from_settings(self, repo_with_mcp, seeded_settings, run_deploy):
        # First deploy to register the server
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert "test-mcp" in settings.get("mcpServers", {})

        # Teardown
        run_deploy("--teardown-mcp", "test-mcp")
        settings_after = read_settings(seeded_settings)
        assert "test-mcp" not in settings_after.get("mcpServers", {})

    def test_teardown_mcp_nonexistent_warns(self, mini_repo, seeded_settings, run_deploy):
        result = run_deploy("--teardown-mcp", "nonexistent")
        assert "not found" in result.stdout


# ---------------------------------------------------------------------------
# Test: dry-run
# ---------------------------------------------------------------------------


class TestMcpDryRun:
    def test_dry_run_no_settings_change(self, repo_with_mcp, seeded_settings, run_deploy):
        before = (seeded_settings / "settings.json").read_text()
        run_deploy("--dry-run", "--no-profile")
        after = (seeded_settings / "settings.json").read_text()
        assert before == after

    def test_dry_run_shows_would_update(self, repo_with_mcp, config_dir, run_deploy):
        result = run_deploy("--dry-run", "--no-profile")
        assert "Would update" in result.stdout
