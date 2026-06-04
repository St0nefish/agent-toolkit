#!/usr/bin/env bash
# worktree-create.sh — Create a git worktree for parallel work.
#
# Usage: worktree-create.sh <branch-name> [--from <base-branch>]
#
# Creates a new linked worktree at:
#   <main-repo-root>/.github/worktrees/<slug>
#
# Keeps git as the source of truth. The base directory is auto-added to
# .gitignore on first use.
#
# Override the base location with WORKTREE_BASE_DIR.
#
# If the branch already exists, attaches it. If it doesn't exist, creates it
# from <base-branch> (defaults to current branch).

set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=worktree-lib.sh
source "$SCRIPTS_DIR/worktree-lib.sh"

usage() {
  echo "Usage: worktree-create.sh <branch-name> [--from <base-branch>]" >&2
  exit 1
}

# --- Argument parsing ---
BRANCH=""
FROM_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -lt 2 ]] && usage
      FROM_BRANCH="$2"
      shift 2
      ;;
    --from=*)
      FROM_BRANCH="${1#--from=}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$BRANCH" ]]; then
        BRANCH="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z "$BRANCH" ]]; then
  echo "Error: branch name is required." >&2
  usage
fi

# --- Validate git repo ---
git_root >/dev/null || {
  echo "Error: not inside a git repository." >&2
  exit 1
}

# --- Determine worktree path ---
BASE_DIR=$(worktree_base_dir)
SLUG=$(slug_from_branch "$BRANCH")
WT_PATH="${BASE_DIR}/${SLUG}"

if [[ -d "$WT_PATH" ]]; then
  echo "Error: worktree directory already exists: $WT_PATH" >&2
  exit 1
fi

# --- Check if branch exists ---
branch_exists() {
  git rev-parse --verify "refs/heads/$1" >/dev/null 2>&1
}

# --- Ensure the in-repo base dir is gitignored (skip if user overrode the location) ---
if [[ -z "${WORKTREE_BASE_DIR:-}" ]]; then
  MAIN_ROOT=$(main_repo_root)
  if [[ -n "$MAIN_ROOT" ]] && ! git -C "$MAIN_ROOT" check-ignore -q ".github/worktrees/.probe" 2>/dev/null; then
    GITIGNORE="$MAIN_ROOT/.gitignore"
    if [[ -f "$GITIGNORE" && -n "$(tail -c1 "$GITIGNORE" 2>/dev/null)" ]]; then
      printf '\n' >>"$GITIGNORE"
    fi
    printf '%s\n' '.github/worktrees/' >>"$GITIGNORE"
    echo "→ Added '.github/worktrees/' to $GITIGNORE"
  fi
fi

# --- Create base directory ---
mkdir -p "$BASE_DIR"

# --- Create worktree ---
if branch_exists "$BRANCH"; then
  # Branch already exists — check it out in the new worktree
  git worktree add "$WT_PATH" "$BRANCH"
else
  # Create new branch
  if [[ -n "$FROM_BRANCH" ]]; then
    git worktree add "$WT_PATH" -b "$BRANCH" "$FROM_BRANCH"
  else
    git worktree add "$WT_PATH" -b "$BRANCH"
  fi
fi

echo ""
echo "✓ Worktree created:"
echo "  Path:   $WT_PATH"
echo "  Branch: $BRANCH"
echo ""
echo "To work in this worktree, run commands with the path prefix, for example:"
echo "  cd $WT_PATH && git status"
echo "  cd $WT_PATH && <your commands>"
echo ""
echo "To clean up when done:"
echo "  git worktree remove $WT_PATH"
