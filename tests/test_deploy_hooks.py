"""Tests for deploy.py hook registration into settings.json.

Port of tests/test-deploy-hooks.sh. Uses synthetic hooks with known
hooks_config rather than relying on the real repo's hooks.
"""

import json

import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_with_hooks(mini_repo):
    """Mini-repo with two synthetic hooks: test-hook (PreToolUse) and async-hook (PostToolUse).

    Also creates a dummy skill so deploy.py doesn't early-return when skills/ is missing.
    """
    mini_repo.create_skill(
        "dummy",
        md_content="---\ndescription: dummy skill for hooks tests\n---\n# dummy\n",
    )
    mini_repo.create_hook(
        "test-hook",
        script_content="#!/bin/bash\nexit 0\n",
        deploy_json={
            "hooks_config": {
                "event": "PreToolUse",
                "matcher": "Bash",
                "command_script": "test-hook.sh",
            }
        },
    )
    mini_repo.create_hook(
        "async-hook",
        script_content="#!/bin/bash\nexit 0\n",
        deploy_json={
            "hooks_config": {
                "event": "PostToolUse",
                "matcher": "Edit|Write",
                "command_script": "async-hook.sh",
                "async": True,
                "timeout": 60,
            }
        },
    )
    return mini_repo


@pytest.fixture
def seeded_settings(config_dir):
    """Seed settings.json with extra keys to verify they are preserved."""
    settings = {"env": {"TEST": "preserved"}, "model": "test-model"}
    (config_dir / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
    return config_dir


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def read_settings(config_dir):
    return json.loads((config_dir / "settings.json").read_text())


# ---------------------------------------------------------------------------
# Test: deploy writes hooks object
# ---------------------------------------------------------------------------


class TestDeployWritesHooksObject:
    def test_hooks_is_object(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert isinstance(settings.get("hooks"), dict)

    def test_pre_tool_use_has_entries(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        entries = settings.get("hooks", {}).get("PreToolUse", [])
        assert len(entries) > 0

    def test_pre_tool_use_matcher_is_bash(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        matcher = settings["hooks"]["PreToolUse"][0]["matcher"]
        assert matcher == "Bash"

    def test_pre_tool_use_command_ends_with_hook_script(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        command = settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        assert command.endswith("test-hook/test-hook.sh")

    def test_pre_tool_use_type_is_command(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        hook_type = settings["hooks"]["PreToolUse"][0]["hooks"][0]["type"]
        assert hook_type == "command"


# ---------------------------------------------------------------------------
# Test: async and timeout hook
# ---------------------------------------------------------------------------


class TestAsyncAndTimeoutHook:
    def test_post_tool_use_has_entries(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        entries = settings.get("hooks", {}).get("PostToolUse", [])
        assert len(entries) > 0

    def test_post_tool_use_matcher(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        matcher = settings["hooks"]["PostToolUse"][0]["matcher"]
        assert matcher == "Edit|Write"

    def test_post_tool_use_async_is_true(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        async_flag = settings["hooks"]["PostToolUse"][0]["hooks"][0]["async"]
        assert async_flag is True

    def test_post_tool_use_timeout_is_60(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        timeout = settings["hooks"]["PostToolUse"][0]["hooks"][0]["timeout"]
        assert timeout == 60


# ---------------------------------------------------------------------------
# Test: other keys preserved after deploy
# ---------------------------------------------------------------------------


class TestOtherKeysPreserved:
    def test_env_test_preserved(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert settings.get("env", {}).get("TEST") == "preserved"

    def test_model_preserved(self, repo_with_hooks, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        assert settings.get("model") == "test-model"


# ---------------------------------------------------------------------------
# Test: idempotency
# ---------------------------------------------------------------------------


def test_idempotent(repo_with_hooks, seeded_settings, run_deploy):
    """Running deploy twice must leave settings.json byte-for-byte identical."""
    run_deploy("--no-profile")
    content_after_first = (seeded_settings / "settings.json").read_text()

    run_deploy("--no-profile")
    content_after_second = (seeded_settings / "settings.json").read_text()

    assert content_after_first == content_after_second


# ---------------------------------------------------------------------------
# Test: append-missing preserves manually added hooks
# ---------------------------------------------------------------------------


class TestAppendMissingPreservesManualHooks:
    def test_custom_event_survives_redeploy(self, repo_with_hooks, seeded_settings, run_deploy):
        """A custom hook event injected manually must survive a re-deploy."""
        run_deploy("--no-profile")

        # Inject a custom hook event into the already-written settings.json
        settings = read_settings(seeded_settings)
        settings.setdefault("hooks", {})["CustomEvent"] = [
            {
                "matcher": "Read",
                "hooks": [{"type": "command", "command": "/usr/bin/true"}],
            }
        ]
        (seeded_settings / "settings.json").write_text(
            json.dumps(settings, indent=2) + "\n"
        )

        # Re-deploy — CustomEvent must survive
        run_deploy("--no-profile")

        settings_after = read_settings(seeded_settings)
        assert "CustomEvent" in settings_after.get("hooks", {})

    def test_deploy_hooks_still_present_after_append(self, repo_with_hooks, seeded_settings, run_deploy):
        """Original deploy hooks remain after a re-deploy that follows manual injection."""
        run_deploy("--no-profile")

        settings = read_settings(seeded_settings)
        settings.setdefault("hooks", {})["CustomEvent"] = [
            {
                "matcher": "Read",
                "hooks": [{"type": "command", "command": "/usr/bin/true"}],
            }
        ]
        (seeded_settings / "settings.json").write_text(
            json.dumps(settings, indent=2) + "\n"
        )

        run_deploy("--no-profile")

        settings_after = read_settings(seeded_settings)
        pre_tool_use = settings_after.get("hooks", {}).get("PreToolUse", [])
        assert len(pre_tool_use) > 0
        assert pre_tool_use[0]["matcher"] == "Bash"


# ---------------------------------------------------------------------------
# Test: --skip-permissions skips hooks management too
# ---------------------------------------------------------------------------


class TestSkipPermissionsSkipsHooks:
    def test_skip_permissions_message_in_output(self, repo_with_hooks, seeded_settings, run_deploy):
        """--skip-permissions must print a message indicating hooks were skipped."""
        # Seed hooks with a known sentinel value
        settings = read_settings(seeded_settings)
        settings["hooks"] = {"Fake": []}
        (seeded_settings / "settings.json").write_text(
            json.dumps(settings, indent=2) + "\n"
        )

        result = run_deploy("--no-profile", "--skip-permissions")
        combined = result.stdout + result.stderr
        assert "Skipped: hooks management" in combined

    def test_skip_permissions_leaves_hooks_unchanged(self, repo_with_hooks, seeded_settings, run_deploy):
        """--skip-permissions must not overwrite the hooks section."""
        settings = read_settings(seeded_settings)
        settings["hooks"] = {"Fake": []}
        (seeded_settings / "settings.json").write_text(
            json.dumps(settings, indent=2) + "\n"
        )

        run_deploy("--no-profile", "--skip-permissions")

        settings_after = read_settings(seeded_settings)
        assert "Fake" in settings_after.get("hooks", {})


# ---------------------------------------------------------------------------
# Fixtures for matcherless / array hooks_config
# ---------------------------------------------------------------------------


@pytest.fixture
def repo_with_matcherless_hook(mini_repo):
    """Mini-repo with a hook that uses array hooks_config and no matcher.

    Simulates the notify-on-stop hook: two events (UserPromptSubmit, Stop),
    both async, neither has a matcher.
    """
    mini_repo.create_skill(
        "dummy",
        md_content="---\ndescription: dummy skill for hooks tests\n---\n# dummy\n",
    )
    mini_repo.create_hook(
        "notify-on-stop",
        script_content="#!/bin/bash\nexit 0\n",
        deploy_json={
            "hooks_config": [
                {
                    "event": "UserPromptSubmit",
                    "command_script": "notify-on-stop.sh",
                    "async": True,
                },
                {
                    "event": "Stop",
                    "command_script": "notify-on-stop.sh",
                    "async": True,
                },
            ]
        },
    )
    return mini_repo


# ---------------------------------------------------------------------------
# Test: matcherless / array hooks_config
# ---------------------------------------------------------------------------


class TestMatcherlessHook:
    def test_both_events_deployed(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        hooks = settings.get("hooks", {})
        assert "UserPromptSubmit" in hooks
        assert "Stop" in hooks

    def test_user_prompt_submit_no_matcher(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        entry = settings["hooks"]["UserPromptSubmit"][0]
        assert "matcher" not in entry

    def test_stop_no_matcher(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        entry = settings["hooks"]["Stop"][0]
        assert "matcher" not in entry

    def test_both_async(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        for event in ("UserPromptSubmit", "Stop"):
            hook_entry = settings["hooks"][event][0]["hooks"][0]
            assert hook_entry.get("async") is True, f"{event} should be async"

    def test_command_paths_correct(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        settings = read_settings(seeded_settings)
        for event in ("UserPromptSubmit", "Stop"):
            command = settings["hooks"][event][0]["hooks"][0]["command"]
            assert command.endswith("notify-on-stop/notify-on-stop.sh")

    def test_idempotent(self, repo_with_matcherless_hook, seeded_settings, run_deploy):
        run_deploy("--no-profile")
        first = (seeded_settings / "settings.json").read_text()
        run_deploy("--no-profile")
        second = (seeded_settings / "settings.json").read_text()
        assert first == second
