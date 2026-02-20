"""Tests for the frontmatter-query skill script."""

import json
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "skills" / "frontmatter-query" / "bin" / "frontmatter-query.py"


def run(args: list[str], cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)] + args,
        capture_output=True,
        text=True,
        cwd=cwd,
    )


def write_md(path: Path, frontmatter: str, body: str = "Hello world.") -> None:
    path.write_text(f"---\n{frontmatter}---\n\n{body}\n")


@pytest.fixture
def sample_dir(tmp_path: Path) -> Path:
    """Create a temp directory with sample markdown files."""
    write_md(
        tmp_path / "a.md",
        textwrap.dedent("""\
            title: Alpha
            tags:
              - python
              - cli
            allowed-tools: Bash
        """),
        "Alpha body.",
    )
    write_md(
        tmp_path / "b.md",
        textwrap.dedent("""\
            title: Bravo
            tags:
              - rust
            allowed-tools: Bash, Read
        """),
        "Bravo body.",
    )
    write_md(
        tmp_path / "c.md",
        textwrap.dedent("""\
            title: Charlie
            tags:
              - python
              - rust
        """),
    )
    # File with no frontmatter
    (tmp_path / "no-fm.md").write_text("# Just a heading\n\nNo frontmatter here.\n")
    # Non-markdown file (should be ignored)
    (tmp_path / "readme.txt").write_text("Not markdown.\n")
    return tmp_path


# --- list ---


def test_list_all(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir)])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 3
    titles = [e["title"] for e in entries]
    assert titles == ["Alpha", "Bravo", "Charlie"]


def test_list_single_file(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir / "a.md")])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 1
    assert entries[0]["title"] == "Alpha"


def test_list_limit(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir), "--limit", "2"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 2


def test_list_keys(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir), "--keys", "title"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    for e in entries:
        assert set(e.keys()) == {"path", "title"}


def test_list_body(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir), "--limit", "1", "--body"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert "body" in entries[0]
    assert "Alpha body." in entries[0]["body"]


def test_list_no_body_by_default(sample_dir: Path) -> None:
    r = run(["list", str(sample_dir), "--limit", "1"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert "body" not in entries[0]
    assert "_content" not in entries[0]


# --- search ---


def test_search_exact(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-k", "title", "-v", "Alpha"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 1
    assert entries[0]["title"] == "Alpha"


def test_search_case_insensitive(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-k", "title", "-v", "alpha"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 1
    assert entries[0]["title"] == "Alpha"


def test_search_list_membership(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-k", "tags", "-v", "python"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 2
    titles = sorted(e["title"] for e in entries)
    assert titles == ["Alpha", "Charlie"]


def test_search_no_match(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-k", "tags", "-v", "java"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert entries == []


def test_search_limit(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-k", "tags", "-v", "python", "--limit", "1"])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert len(entries) == 1


# --- tags ---


def test_tags_default(sample_dir: Path) -> None:
    r = run(["tags", str(sample_dir)])
    assert r.returncode == 0
    result = json.loads(r.stdout)
    assert result["python"] == 2
    assert result["rust"] == 2
    assert result["cli"] == 1
    # Verify sorted by count desc
    counts = list(result.values())
    assert counts == sorted(counts, reverse=True)


def test_tags_custom_key(sample_dir: Path) -> None:
    r = run(["tags", str(sample_dir), "-k", "title"])
    assert r.returncode == 0
    result = json.loads(r.stdout)
    assert result == {"Alpha": 1, "Bravo": 1, "Charlie": 1}


# --- error cases ---


def test_nonexistent_path(tmp_path: Path) -> None:
    r = run(["list", str(tmp_path / "nonexistent")])
    assert r.returncode == 2


def test_no_command() -> None:
    r = run([])
    assert r.returncode == 2  # argparse exits with 2 for missing required args


def test_search_missing_key(sample_dir: Path) -> None:
    r = run(["search", str(sample_dir), "-v", "foo"])
    assert r.returncode == 2  # argparse exits with 2


def test_empty_dir(tmp_path: Path) -> None:
    r = run(["list", str(tmp_path)])
    assert r.returncode == 0
    entries = json.loads(r.stdout)
    assert entries == []
