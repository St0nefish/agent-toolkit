# deploy/linker.py - Symlink creation and cleanup

from pathlib import Path


def ensure_link(link: Path, target: Path, label: str, dry_run: bool,
                for_dir: bool = False) -> str:
    """Create or verify a symlink from link -> target.

    - In dry-run mode: prints the ln command that would run (no "Linked:" line)
    - If symlink already points to target: prints "OK: <label>"
    - Otherwise: creates/overwrites the symlink and prints "Linked: <label>"

    Returns "OK" or "Linked".
    """
    if not dry_run:
        try:
            existing = link.readlink()
            if existing == target:
                print(f"  OK: {label}")
                return "OK"
        except (OSError, ValueError):
            pass

    if dry_run:
        flag = "-sfn" if for_dir else "-sf"
        print(f"  > ln {flag} {target} {link}")
    else:
        try:
            link.unlink(missing_ok=True)
        except OSError:
            pass
        link.symlink_to(target)
        print(f"  Linked: {label}")

    return "Linked"


def cleanup_broken_symlinks(directory: Path, filter_type: str, dry_run: bool):
    """Remove broken symlinks in a directory.

    filter_type: '' (all), 'dir' (only dir symlinks), 'file' (only file symlinks)

    For the skills directory (filter_type != 'dir'), also cleans subdirectories
    that contain only broken symlinks.
    """
    if not directory.is_dir():
        return

    for link in directory.iterdir():
        if not link.is_symlink():
            continue
        if link.exists():
            continue
        if dry_run:
            print(f"  > Would remove broken symlink: {link}")
        else:
            link.unlink(missing_ok=True)
            print(f"  Cleaned: broken symlink {link} (target gone)")

    if filter_type != "dir":
        for subdir in directory.iterdir():
            if not subdir.is_dir():
                continue
            if subdir.is_symlink():
                continue
            has_valid = False
            entries = list(subdir.iterdir())
            for entry in entries:
                if entry.is_symlink() and entry.exists():
                    has_valid = True
                    break
            if not has_valid:
                for entry in entries:
                    if entry.is_symlink():
                        if dry_run:
                            print(f"  > Would remove broken symlink: {entry}")
                        else:
                            entry.unlink(missing_ok=True)
                            print(f"  Cleaned: broken symlink {entry} (target gone)")
                if dry_run:
                    print(f"  > Would remove empty skills subdirectory: {subdir}")
                else:
                    try:
                        subdir.rmdir()
                        print(f"  Cleaned: empty skills subdirectory {subdir}")
                    except OSError:
                        pass


def is_globally_deployed(deploy_name: str, global_skills_base: Path) -> bool:
    """Return True if a skill is already deployed globally.

    Checks for <deploy_name>/SKILL.md in the global skills directory.
    """
    return (global_skills_base / deploy_name / "SKILL.md").is_symlink()
