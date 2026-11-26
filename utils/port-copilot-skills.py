#!/usr/bin/env python3
"""Generate real Copilot copies of the Claude skills that were symlinked.

Copilot CLI reads only `name`, `description`, `license` and `allowed-tools`
from a SKILL.md and has no `when_to_use`, so a symlinked skills/ directory
leaves it without trigger text. For each plugin in PLUGINS this replaces
plugins-copilot/<p>/skills (a symlink) with a real directory holding a real
file copy of every file under plugins-claude/<p>/skills, modes preserved. Each
SKILL.md goes through fold_when_to_use (utils/skill-frontmatter.py), so
`when_to_use` is merged into `description`. Files in the destination that no
longer exist in the source are deleted. A folded description over the Agent
Skills limit of 1024 characters is a hard error.

Usage:
  python3 utils/port-copilot-skills.py           # regenerate
  python3 utils/port-copilot-skills.py --check   # exit non-zero on drift, no writes
"""

import os
import shutil
import stat
import sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

_here = Path(__file__).parent
_spec = spec_from_file_location("skill_frontmatter", _here / "skill-frontmatter.py")
_fm = module_from_spec(_spec)
_spec.loader.exec_module(_fm)

ROOT = _here.parent
PLUGINS = [
    "agentic-ide",
    "convert-doc",
    "elevated-edit",
    "freecad",
    "git-tools",
    "image",
    "stl-game-config",
]
MAX_DESCRIPTION = 1024


def source_files(src: Path):
    """Relative paths of every file under src (symlinks followed)."""
    out = []
    for dirpath, _dirs, files in os.walk(src, followlinks=True):
        for f in files:
            out.append(Path(dirpath, f).relative_to(src))
    return sorted(out)


def render(src_file: Path, rel: Path) -> bytes:
    data = src_file.read_bytes()
    if rel.name != "SKILL.md":
        return data
    try:
        text = _fm.fold_when_to_use(data.decode())
        desc = _fm.frontmatter_value(text, "description") or ""
    except ValueError as e:
        print(f"{src_file}: {e}", file=sys.stderr)
        sys.exit(1)
    if len(desc) > MAX_DESCRIPTION:
        sys.exit(
            f"ERROR: {src_file.relative_to(ROOT)}: folded description is "
            f"{len(desc)} chars (limit {MAX_DESCRIPTION}); shorten description/when_to_use"
        )
    return text.encode()


def dest_files(dst: Path):
    out = []
    for dirpath, _dirs, files in os.walk(dst):
        for f in files:
            out.append(Path(dirpath, f).relative_to(dst))
    return out


def main(check: bool) -> int:
    drift = []

    def note(msg):
        drift.append(msg)
        print(f"DRIFT: {msg}", file=sys.stderr)

    # Render everything and look for symlinks first, so any failure leaves the
    # tree untouched.
    wants = {}
    for p in PLUGINS:
        src = ROOT / "plugins-claude" / p / "skills"
        wants[p] = {rel: render(src / rel, rel) for rel in source_files(src)}
    for p in PLUGINS:
        dst = ROOT / "plugins-copilot" / p / "skills"
        if dst.is_symlink() or not dst.is_dir():
            continue  # the top-level symlink is expected and replaced
        for dirpath, dirs, files in os.walk(dst):
            for n in dirs + files:
                if os.path.islink(os.path.join(dirpath, n)):
                    sys.exit(
                        f"ERROR: {Path(dirpath, n).relative_to(ROOT)} is a symlink "
                        "under a destination skills dir; remove it and re-run"
                    )

    for p in PLUGINS:
        src = ROOT / "plugins-claude" / p / "skills"
        dst = ROOT / "plugins-copilot" / p / "skills"
        label = dst.relative_to(ROOT)
        want = wants[p]

        if dst.is_symlink() or (dst.exists() and not dst.is_dir()):
            note(f"{label} is a symlink/non-directory (run utils/port-copilot-skills.py)")
            if not check:
                dst.unlink()
        have = set(dest_files(dst)) if dst.is_dir() and not dst.is_symlink() else set()

        for rel in sorted(have - set(want)):
            note(f"{label}/{rel} has no source (run utils/port-copilot-skills.py)")
            if not check:
                (dst / rel).unlink()
        for rel, data in sorted(want.items()):
            out = dst / rel
            mode = stat.S_IMODE((src / rel).stat().st_mode)
            if out.is_symlink():
                note(f"{label}/{rel} is a symlink")
            elif not out.exists() or out.read_bytes() != data:
                note(f"{label}/{rel} differs from its Claude original")
            elif stat.S_IMODE(out.stat().st_mode) != mode:
                note(f"{label}/{rel} mode differs from its Claude original")
            else:
                continue
            if not check:
                out.parent.mkdir(parents=True, exist_ok=True)
                if out.is_symlink():
                    out.unlink()
                out.write_bytes(data)
                out.chmod(mode)
        if not check and dst.is_dir():
            # Prune directories left empty by deleted files.
            for dirpath, _d, _f in sorted(os.walk(dst, topdown=False)):
                if not os.listdir(dirpath) and Path(dirpath) != dst:
                    os.rmdir(dirpath)
            print(f"ported: {label}")

    if check:
        if not drift:
            print("no drift — plugins-copilot skills match their Claude originals")
        return 1 if drift else 0
    return 0


if __name__ == "__main__":
    if any(a != "--check" for a in sys.argv[1:]):
        sys.exit(f"usage: {sys.argv[0]} [--check]")
    sys.exit(main(bool(sys.argv[1:])))
