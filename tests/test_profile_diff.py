"""Tests for .claude/skills/deploy/bin/profile-diff (Python version)."""

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROFILE_DIFF = REPO_ROOT / ".claude" / "skills" / "deploy" / "bin" / "profile-diff"


def run_profile_diff(discover_json: dict, profile_path: Path) -> dict:
    result = subprocess.run(
        [sys.executable, str(PROFILE_DIFF), str(profile_path)],
        input=json.dumps(discover_json),
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def test_no_drift(tmp_path):
    profile = tmp_path / "profile.json"
    profile.write_text(json.dumps({
        "skills": {"foo": {"enabled": True}, "bar": {"enabled": True}},
        "hooks": {"myhook": {"enabled": True}},
        "mcp": {},
    }))
    discover = {
        "skills": [{"name": "foo"}, {"name": "bar"}],
        "hooks": [{"name": "myhook"}],
        "mcp": [],
    }
    output = run_profile_diff(discover, profile)
    assert output["added"]["skills"] == []
    assert output["removed"]["skills"] == []
    assert output["added"]["hooks"] == []
    assert output["removed"]["hooks"] == []


def test_new_skill(tmp_path):
    profile = tmp_path / "profile.json"
    profile.write_text(json.dumps({
        "skills": {"foo": {"enabled": True}},
        "hooks": {},
        "mcp": {},
    }))
    discover = {
        "skills": [{"name": "foo"}, {"name": "image"}],
        "hooks": [],
        "mcp": [],
    }
    output = run_profile_diff(discover, profile)
    assert output["added"]["skills"] == ["image"]
    assert output["removed"]["skills"] == []


def test_removed_skill(tmp_path):
    profile = tmp_path / "profile.json"
    profile.write_text(json.dumps({
        "skills": {"foo": {"enabled": True}, "paste-image-macos": {"enabled": True}},
        "hooks": {},
        "mcp": {},
    }))
    discover = {"skills": [{"name": "foo"}], "hooks": [], "mcp": []}
    output = run_profile_diff(discover, profile)
    assert output["removed"]["skills"] == ["paste-image-macos"]
    assert output["added"]["skills"] == []


def test_new_hook(tmp_path):
    profile = tmp_path / "profile.json"
    profile.write_text(json.dumps({"skills": {}, "hooks": {}, "mcp": {}}))
    discover = {"skills": [], "hooks": [{"name": "bash-safety"}], "mcp": []}
    output = run_profile_diff(discover, profile)
    assert output["added"]["hooks"] == ["bash-safety"]


def test_mixed_drift(tmp_path):
    profile = tmp_path / "profile.json"
    profile.write_text(json.dumps({
        "skills": {"old-skill": {"enabled": True}},
        "hooks": {"old-hook": {"enabled": True}},
        "mcp": {},
    }))
    discover = {
        "skills": [{"name": "new-skill"}],
        "hooks": [{"name": "new-hook"}],
        "mcp": [],
    }
    output = run_profile_diff(discover, profile)
    assert output["added"]["skills"] == ["new-skill"]
    assert output["removed"]["skills"] == ["old-skill"]
    assert output["added"]["hooks"] == ["new-hook"]
    assert output["removed"]["hooks"] == ["old-hook"]
