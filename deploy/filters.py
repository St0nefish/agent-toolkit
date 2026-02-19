# deploy/filters.py - Include/exclude filtering


def is_filtered_out(name: str, include: list, exclude: list) -> bool:
    """Return True if the item should be skipped by --include/--exclude.

    include/exclude are lists of tool names (already split/normalized).
    """
    if include:
        return name not in include
    if exclude:
        return name in exclude
    return False
