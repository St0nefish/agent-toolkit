"""
Shared pytest fixtures for the deploy.py test suite.

Pattern mirrors the bash test files:
  1. Create a temp mini-repo with deploy.py copied in.
  2. Create synthetic skills / hooks via helper methods.
  3. Create a temp CLAUDE_CONFIG_DIR.
  4. Run `python3 deploy.py` via subprocess with CLAUDE_CONFIG_DIR set.
  5. Assert on symlinks, output, and settings.json contents.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

# Absolute path to deploy-py/ (one level up from tests/)
DEPLOY_PY_ROOT = Path(__file__).resolve().parent.parent
# Absolute path to the real repo root (two levels up from tests/)
REPO_ROOT = DEPLOY_PY_ROOT.parent


@pytest.fixture
def config_dir(tmp_path):
    """Fresh temp directory acting as CLAUDE_CONFIG_DIR."""
    d = tmp_path / "claude_config"
    d.mkdir()
    return d


class MiniRepo:
    """Helper returned by the mini_repo fixture."""

    def __init__(self, root: Path) -> None:
        self._root = root
        # Mirror the real layout: deploy.py and deploy/ live under deploy-py/
        deploy_py_dir = root / "deploy-py"
        deploy_py_dir.mkdir()
        shutil.copy2(DEPLOY_PY_ROOT / "deploy.py", deploy_py_dir / "deploy.py")
        shutil.copytree(DEPLOY_PY_ROOT / "deploy", deploy_py_dir / "deploy")

    @property
    def root(self) -> Path:
        return self._root

    def create_skill(
        self,
        name: str,
        md_content: str = "# skill",
        script_content: str = "#!/bin/bash\necho hello",
        extra_mds: dict | None = None,
        deploy_json: dict | None = None,
    ) -> Path:
        skill_dir = self._root / "skills" / name
        bin_dir = skill_dir / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)

        script = bin_dir / name
        script.write_text(script_content)
        script.chmod(0o755)

        (skill_dir / f"{name}.md").write_text(md_content)

        if extra_mds:
            for filename, content in extra_mds.items():
                (skill_dir / filename).write_text(content)

        if deploy_json is not None:
            (skill_dir / "deploy.json").write_text(
                json.dumps(deploy_json, indent=2) + "\n"
            )

        return skill_dir

    def create_hook(
        self,
        name: str,
        script_content: str = "#!/bin/bash\necho hook",
        deploy_json: dict | None = None,
    ) -> Path:
        hook_dir = self._root / "hooks" / name
        hook_dir.mkdir(parents=True, exist_ok=True)

        script = hook_dir / f"{name}.sh"
        script.write_text(script_content)
        script.chmod(0o755)

        if deploy_json is not None:
            (hook_dir / "deploy.json").write_text(
                json.dumps(deploy_json, indent=2) + "\n"
            )

        return hook_dir

    def create_mcp(
        self,
        name: str,
        deploy_json: dict | None = None,
        setup_sh: str | None = None,
    ) -> Path:
        mcp_dir = self._root / "mcp" / name
        mcp_dir.mkdir(parents=True, exist_ok=True)

        if deploy_json is not None:
            (mcp_dir / "deploy.json").write_text(
                json.dumps(deploy_json, indent=2) + "\n"
            )

        if setup_sh is not None:
            script = mcp_dir / "setup.sh"
            script.write_text(setup_sh)
            script.chmod(0o755)

        return mcp_dir

    def create_permission_group(
        self,
        name: str,
        permissions: dict | None = None,
        deploy_overrides: dict | None = None,
    ) -> Path:
        perm_dir = self._root / "permissions"
        perm_dir.mkdir(parents=True, exist_ok=True)

        data = {}
        if permissions is not None:
            data["permissions"] = permissions
        if deploy_overrides:
            data.update(deploy_overrides)

        path = perm_dir / f"{name}.json"
        path.write_text(json.dumps(data, indent=2) + "\n")
        return path

    def create_permission_group_local(
        self,
        name: str,
        overrides: dict,
    ) -> Path:
        perm_dir = self._root / "permissions"
        perm_dir.mkdir(parents=True, exist_ok=True)

        path = perm_dir / f"{name}.local.json"
        path.write_text(json.dumps(overrides, indent=2) + "\n")
        return path

    def create_deploy_json(self, config_dict: dict) -> Path:
        path = self._root / "deploy.json"
        path.write_text(json.dumps(config_dict, indent=2) + "\n")
        return path

    def create_deploy_local_json(self, config_dict: dict) -> Path:
        path = self._root / "deploy.local.json"
        path.write_text(json.dumps(config_dict, indent=2) + "\n")
        return path


@pytest.fixture
def mini_repo(tmp_path) -> MiniRepo:
    deploy_py = DEPLOY_PY_ROOT / "deploy.py"
    if not deploy_py.exists():
        pytest.skip(f"deploy.py not found at {deploy_py}")

    repo_dir = tmp_path / "mini_repo"
    repo_dir.mkdir()
    return MiniRepo(repo_dir)


@pytest.fixture
def run_deploy(mini_repo: MiniRepo, config_dir: Path):
    """Returns a callable that runs deploy.py with given args."""
    default_config_dir = config_dir

    def _run(
        *args: str,
        config_dir: Path | None = None,
        env_overrides: dict | None = None,
    ) -> subprocess.CompletedProcess:
        effective_config_dir = (
            config_dir if config_dir is not None else default_config_dir
        )

        env = os.environ.copy()
        if effective_config_dir is not None:
            env["CLAUDE_CONFIG_DIR"] = str(effective_config_dir)
        if env_overrides:
            env.update(env_overrides)

        return subprocess.run(
            [sys.executable, "deploy-py/deploy.py", *args],
            cwd=mini_repo.root,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    return _run
