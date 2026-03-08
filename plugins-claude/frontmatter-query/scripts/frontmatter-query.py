#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["python-frontmatter"]
# ///
"""Query YAML frontmatter across markdown files."""

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path

import frontmatter


def find_md_files(path: Path) -> list[Path]:
    """Recursively find all .md files under path."""
    if path.is_file():
        return [path] if path.suffix == ".md" else []
    results = []
    for root, _dirs, files in os.walk(path):
        for f in sorted(files):
            if f.endswith(".md"):
                results.append(Path(root) / f)
    return results


def parse_frontmatter(filepath: Path) -> dict | None:
    """Parse frontmatter from a file. Returns None on failure or empty frontmatter."""
    try:
        post = frontmatter.load(str(filepath))
        if not post.metadata:
            return None
        return {"path": str(filepath), "_content": post.content, **post.metadata}
    except Exception:
        return None


def filter_keys(entry: dict, keys: list[str] | None, include_body: bool) -> dict:
    """Filter entry to only requested keys."""
    if not include_body:
        entry = {k: v for k, v in entry.items() if k != "_content"}
    else:
        # Rename _content to body in output
        if "_content" in entry:
            entry = {**entry, "body": entry.pop("_content")}

    if keys:
        keep = {"path"} | set(keys)
        if include_body:
            keep.add("body")
        entry = {k: v for k, v in entry.items() if k in keep}
    else:
        entry = {k: v for k, v in entry.items() if k != "_content"}

    return entry


def matches_value(actual, query: str) -> bool:
    """Check if actual value matches query (case-insensitive, list membership)."""
    query_lower = query.lower()
    if isinstance(actual, list):
        return any(str(item).lower() == query_lower for item in actual)
    return str(actual).lower() == query_lower


def cmd_list(args: argparse.Namespace) -> None:
    """List frontmatter from all markdown files."""
    path = Path(args.path)
    if not path.exists():
        print(f"Path not found: {path}", file=sys.stderr)
        sys.exit(2)

    files = find_md_files(path)
    entries = []
    for f in files:
        entry = parse_frontmatter(f)
        if entry is not None:
            entries.append(filter_keys(entry, args.keys, args.body))

    if args.limit and args.limit > 0:
        entries = entries[: args.limit]

    json.dump(entries, sys.stdout, indent=2, default=str)
    print()


def cmd_search(args: argparse.Namespace) -> None:
    """Search frontmatter by key-value pair."""
    path = Path(args.path)
    if not path.exists():
        print(f"Path not found: {path}", file=sys.stderr)
        sys.exit(2)

    files = find_md_files(path)
    entries = []
    for f in files:
        entry = parse_frontmatter(f)
        if entry is None:
            continue
        actual = entry.get(args.key)
        if actual is not None and matches_value(actual, args.value):
            entries.append(filter_keys(entry, args.keys, args.body))

    if args.limit and args.limit > 0:
        entries = entries[: args.limit]

    json.dump(entries, sys.stdout, indent=2, default=str)
    print()


def cmd_tags(args: argparse.Namespace) -> None:
    """Count occurrences of each value for a given key (default: tags)."""
    path = Path(args.path)
    if not path.exists():
        print(f"Path not found: {path}", file=sys.stderr)
        sys.exit(2)

    key = args.key or "tags"
    files = find_md_files(path)
    counter: Counter = Counter()
    for f in files:
        entry = parse_frontmatter(f)
        if entry is None:
            continue
        val = entry.get(key)
        if val is None:
            continue
        if isinstance(val, list):
            for item in val:
                counter[str(item)] += 1
        else:
            counter[str(val)] += 1

    # Sort by count descending, then alphabetically
    result = dict(sorted(counter.items(), key=lambda x: (-x[1], x[0])))
    json.dump(result, sys.stdout, indent=2)
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query YAML frontmatter across markdown files."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Shared arguments
    def add_common_args(p: argparse.ArgumentParser) -> None:
        p.add_argument("path", nargs="?", default=".", help="File or directory to scan")
        p.add_argument("--limit", type=int, default=0, help="Max results to return")
        p.add_argument("--body", action="store_true", help="Include markdown body")
        p.add_argument(
            "--keys", type=str, default=None, help="Comma-separated keys to include"
        )

    # list
    p_list = subparsers.add_parser("list", help="List frontmatter from all files")
    add_common_args(p_list)
    p_list.set_defaults(func=cmd_list)

    # search
    p_search = subparsers.add_parser("search", help="Search by key-value pair")
    add_common_args(p_search)
    p_search.add_argument("-k", "--key", required=True, help="Frontmatter key to match")
    p_search.add_argument(
        "-v", "--value", required=True, help="Value to match (case-insensitive)"
    )
    p_search.set_defaults(func=cmd_search)

    # tags
    p_tags = subparsers.add_parser(
        "tags", help="Count values for a key (default: tags)"
    )
    p_tags.add_argument(
        "path", nargs="?", default=".", help="File or directory to scan"
    )
    p_tags.add_argument(
        "-k", "--key", default=None, help="Key to aggregate (default: tags)"
    )
    p_tags.set_defaults(func=cmd_tags)

    args = parser.parse_args()

    # Parse --keys into a list
    if hasattr(args, "keys") and args.keys:
        args.keys = [k.strip() for k in args.keys.split(",")]

    args.func(args)


if __name__ == "__main__":
    main()
