"""Tests for deploy.discovery.profile_diff (unit tests)."""

import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from deploy.discovery import profile_diff


def test_no_drift():
    profile = {
        "skills": {"foo": {"enabled": True}, "bar": {"enabled": True}},
        "hooks": {"myhook": {"enabled": True}},
        "mcp": {},
    }
    discover = {
        "skills": [{"name": "foo"}, {"name": "bar"}],
        "hooks": [{"name": "myhook"}],
        "mcp": [],
    }
    output = profile_diff(discover, profile)
    assert output["added"]["skills"] == []
    assert output["removed"]["skills"] == []
    assert output["added"]["hooks"] == []
    assert output["removed"]["hooks"] == []


def test_new_skill():
    profile = {
        "skills": {"foo": {"enabled": True}},
        "hooks": {},
        "mcp": {},
    }
    discover = {
        "skills": [{"name": "foo"}, {"name": "image"}],
        "hooks": [],
        "mcp": [],
    }
    output = profile_diff(discover, profile)
    assert output["added"]["skills"] == ["image"]
    assert output["removed"]["skills"] == []


def test_removed_skill():
    profile = {
        "skills": {"foo": {"enabled": True}, "paste-image-macos": {"enabled": True}},
        "hooks": {},
        "mcp": {},
    }
    discover = {"skills": [{"name": "foo"}], "hooks": [], "mcp": []}
    output = profile_diff(discover, profile)
    assert output["removed"]["skills"] == ["paste-image-macos"]
    assert output["added"]["skills"] == []


def test_new_hook():
    profile = {"skills": {}, "hooks": {}, "mcp": {}}
    discover = {"skills": [], "hooks": [{"name": "bash-safety"}], "mcp": []}
    output = profile_diff(discover, profile)
    assert output["added"]["hooks"] == ["bash-safety"]


def test_mixed_drift():
    profile = {
        "skills": {"old-skill": {"enabled": True}},
        "hooks": {"old-hook": {"enabled": True}},
        "mcp": {},
    }
    discover = {
        "skills": [{"name": "new-skill"}],
        "hooks": [{"name": "new-hook"}],
        "mcp": [],
    }
    output = profile_diff(discover, profile)
    assert output["added"]["skills"] == ["new-skill"]
    assert output["removed"]["skills"] == ["old-skill"]
    assert output["added"]["hooks"] == ["new-hook"]
    assert output["removed"]["hooks"] == ["old-hook"]
