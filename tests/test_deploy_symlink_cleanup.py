"""Tests for deploy.py broken symlink cleanup.

Port of tests/test-deploy-symlink-cleanup.sh.

Verifies that broken symlinks in tools/, commands/, and hooks/ are cleaned up
before deployment, while valid symlinks are left alone.
"""

import pytest


MD_CONTENT = "---\ndescription: Cleanup test tool\n---\n# Cleanup Test\n"


# ===== Test 1: Broken tool symlink cleaned =====

def test_broken_tool_symlink_cleaned(mini_repo, config_dir, run_deploy):
    """A broken symlink in tools/ is removed and a cleanup message is emitted."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)

    tools_dir = config_dir / "tools"
    tools_dir.mkdir(parents=True)

    broken = tools_dir / "gone-tool"
    broken.symlink_to("/nonexistent/gone-tool")
    assert broken.is_symlink()

    result = run_deploy("--no-profile", "--skip-permissions")
    output = result.stdout + result.stderr

    assert not broken.is_symlink(), "broken tool symlink should have been removed"
    assert "broken symlink" in output.lower() and "gone-tool" in output, (
        f"expected cleanup message mentioning 'broken symlink' and 'gone-tool', got:\n{output}"
    )


# ===== Test 2: Broken command symlink cleaned =====

def test_broken_command_symlink_cleaned(mini_repo, config_dir, run_deploy):
    """A broken .md symlink in commands/ is removed."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)

    commands_dir = config_dir / "commands"
    commands_dir.mkdir(parents=True)

    broken = commands_dir / "gone.md"
    broken.symlink_to("/nonexistent/gone.md")
    assert broken.is_symlink()

    result = run_deploy("--no-profile", "--skip-permissions")

    assert not broken.is_symlink(), "broken command symlink should have been removed"


# ===== Test 3: Broken hook symlink cleaned =====

def test_broken_hook_symlink_cleaned(mini_repo, config_dir, run_deploy):
    """A broken symlink in hooks/ is removed."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)
    mini_repo.create_hook("real-hook", script_content="#!/usr/bin/env bash\necho ok\n")

    hooks_dir = config_dir / "hooks"
    hooks_dir.mkdir(parents=True)

    broken = hooks_dir / "gone-hook"
    broken.symlink_to("/nonexistent/gone-hook")
    assert broken.is_symlink()

    result = run_deploy("--no-profile", "--skip-permissions")

    assert not broken.is_symlink(), "broken hook symlink should have been removed"


# ===== Test 4: Valid symlinks untouched =====

def test_valid_symlinks_untouched(mini_repo, config_dir, run_deploy, tmp_path):
    """Symlinks that point to existing targets are left alone."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)

    tools_dir = config_dir / "tools"
    commands_dir = config_dir / "commands"
    tools_dir.mkdir(parents=True)
    commands_dir.mkdir(parents=True)

    valid_target_dir = tmp_path / "real-tool-dir"
    valid_target_dir.mkdir()
    valid_tool_link = tools_dir / "valid-tool"
    valid_tool_link.symlink_to(valid_target_dir)

    valid_target_md = tmp_path / "real.md"
    valid_target_md.write_text("# real\n")
    valid_md_link = commands_dir / "valid.md"
    valid_md_link.symlink_to(valid_target_md)

    result = run_deploy("--no-profile", "--skip-permissions")

    assert valid_tool_link.is_symlink(), "valid tool symlink should not have been removed"
    assert valid_md_link.is_symlink(), "valid command symlink should not have been removed"


# ===== Test 5: Dry-run doesn't remove broken symlinks =====

def test_dry_run_does_not_remove_broken_symlinks(mini_repo, config_dir, run_deploy):
    """With --dry-run, broken symlinks are reported but not actually removed."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)

    tools_dir = config_dir / "tools"
    tools_dir.mkdir(parents=True)

    broken = tools_dir / "dry-run-tool"
    broken.symlink_to("/nonexistent/dry-run-tool")
    assert broken.is_symlink()

    result = run_deploy("--no-profile", "--skip-permissions", "--dry-run")
    output = result.stdout + result.stderr

    assert broken.is_symlink(), "dry-run must not remove the broken symlink"
    assert "would remove" in output.lower() and "dry-run-tool" in output, (
        f"expected 'Would remove' message mentioning 'dry-run-tool', got:\n{output}"
    )


# ===== Test 6: Broken subdirectory cleaned =====

def test_broken_subdirectory_cleaned(mini_repo, config_dir, run_deploy):
    """A commands/ subdirectory whose contents are all broken symlinks is removed."""
    mini_repo.create_skill("cleanup-test", md_content=MD_CONTENT)

    subdir = config_dir / "commands" / "gone-multi"
    subdir.mkdir(parents=True)

    (subdir / "a.md").symlink_to("/nonexistent/a.md")
    (subdir / "b.md").symlink_to("/nonexistent/b.md")

    result = run_deploy("--no-profile", "--skip-permissions")
    output = result.stdout + result.stderr

    assert not subdir.exists(), "broken commands subdirectory should have been removed"
    assert "empty commands subdirectory" in output.lower(), (
        f"expected 'empty commands subdirectory' message, got:\n{output}"
    )
