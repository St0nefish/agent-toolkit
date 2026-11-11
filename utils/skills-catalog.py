#!/usr/bin/env python3
"""skills-catalog.py — generate skills-catalog/, the HTTP catalog of the
OpenCode skills in this repo.

OpenCode's `skills` config accepts local dirs or an HTTP catalog (see
opencode.ai/docs/skills). Machines without an agent-toolkit checkout point at

  https://raw.githubusercontent.com/St0nefish/agent-toolkit/master/skills-catalog/

so the catalog must live in the repo, in the layout the spec requires:
index.json listing {name, version, files}, with each file served from
<base>/<name>/<file>. version is a content hash, so any edit to a skill
changes its version and refreshes OpenCode's cache — the spec has no other
update signal.

Sources are the two OpenCode skill dirs. Hidden files and node_modules are
skipped (OpenCode skips them in local sources too, and a dotfile could never
be fetched safely). Exec bits are irrelevant: every skill invokes its scripts
as `bash scripts/...`, and HTTP downloads carry no mode anyway.

Usage:
  python3 utils/skills-catalog.py           # regenerate skills-catalog/
  python3 utils/skills-catalog.py --check   # exit non-zero on drift, no writes
"""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "skills-catalog"
SOURCES = [
    ROOT / "plugins-opencode" / "git-tools" / "skills",
    ROOT / "plugins-opencode" / "session" / "skills",
]


def skill_files(skill_dir: Path) -> list[Path]:
    """All catalog files of one skill, relative to the skill dir, sorted."""
    files = []
    for p in sorted(skill_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(skill_dir)
        if any(part.startswith(".") or part == "node_modules" for part in rel.parts):
            continue
        files.append(rel)
    return files


def build() -> dict:
    """{name: {dir: Path, files: [relpaths], version: hash}} for every skill."""
    skills = {}
    for src in SOURCES:
        for skill_dir in sorted(p for p in src.iterdir() if p.is_dir()):
            entry_file = skill_dir / "SKILL.md"
            if not entry_file.is_file():
                sys.exit(f"skills-catalog: {skill_dir} has no SKILL.md")
            if skill_dir.name in skills:
                sys.exit(f"skills-catalog: duplicate skill id {skill_dir.name}")
            files = skill_files(skill_dir)
            h = hashlib.sha256()
            for rel in files:
                h.update(str(rel).encode())
                h.update(b"\0")
                h.update((skill_dir / rel).read_bytes())
                h.update(b"\0")
            skills[skill_dir.name] = {
                "dir": skill_dir,
                "files": [rel.as_posix() for rel in files],
                "version": h.hexdigest()[:12],
            }
    return skills


def render(out: Path, skills: dict) -> None:
    """Write the catalog tree (layout the HTTP-catalog spec mandates)."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    index = {
        "skills": [
            {"name": name, "version": s["version"], "files": s["files"]}
            for name, s in sorted(skills.items())
        ]
    }
    (out / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    for name, s in skills.items():
        for rel in s["files"]:
            dst = out / name / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(s["dir"] / rel, dst)


def check(tmp: Path, skills: dict) -> int:
    """Compare the committed skills-catalog/ against a fresh render."""
    tmp_out = tmp / "skills-catalog"
    render(tmp_out, skills)
    committed = set()
    if OUT.exists():
        committed = {p.relative_to(OUT) for p in OUT.rglob("*") if p.is_file()}
    fresh = {p.relative_to(tmp_out) for p in tmp_out.rglob("*") if p.is_file()}
    rc = 0
    for rel in sorted(committed - fresh):
        print(
            f"DRIFT: skills-catalog/{rel} is not generated from any skill (run utils/skills-catalog.py)",
            file=sys.stderr,
        )
        rc = 1
    for rel in sorted(fresh - committed):
        print(
            f"DRIFT: skills-catalog/{rel} missing (run utils/skills-catalog.py)",
            file=sys.stderr,
        )
        rc = 1
    for rel in sorted(fresh & committed):
        if not (OUT / rel).read_bytes() == (tmp_out / rel).read_bytes():
            print(
                f"DRIFT: skills-catalog/{rel} differs from its skill source (run utils/skills-catalog.py)",
                file=sys.stderr,
            )
            rc = 1
    return rc


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "generate"
    if mode not in ("--check", "generate"):
        sys.exit(f"usage: {sys.argv[0]} [--check]")
    skills = build()
    if mode == "--check":
        with tempfile.TemporaryDirectory() as td:
            rc = check(Path(td), skills)
        if rc == 0:
            print("no drift — skills-catalog/ matches the skill sources")
        return rc
    render(OUT, skills)
    print(
        f"generated skills-catalog/: {len(skills)} skills, "
        f"{sum(len(s['files']) for s in skills.values())} files"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
