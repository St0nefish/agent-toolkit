# deploy/filters.py - Condition checks and include/exclude filtering

import subprocess
from pathlib import Path


def check_condition(item_dir: Path) -> bool:
    """Run condition.sh if present. Returns True if condition is met (deploy)."""
    cond = item_dir / "condition.sh"
    if not cond.exists():
        return True
    result = subprocess.run(
        [str(cond)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def is_filtered_out(name: str, include: list, exclude: list) -> bool:
    """Return True if the item should be skipped by --include/--exclude.

    include/exclude are lists of tool names (already split/normalized).
    """
    if include:
        return name not in include
    if exclude:
        return name in exclude
    return False
