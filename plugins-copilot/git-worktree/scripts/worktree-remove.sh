#!/usr/bin/env bash
# worktree-remove.sh — Remove a linked git worktree.
#
# Usage: worktree-remove.sh <path-or-name> [--delete-branch] [--force]
#
# <path-or-name> can be:
#   - An absolute path to the worktree directory
#   - A slug name (looked up inside the worktree base dir)
#
# --delete-branch  Also delete the worktree's branch (safe delete: git branch -d)
# --force          Force removal even if the worktree has uncommitted changes

set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=worktree-lib.sh
source "$SCRIPTS_DIR/worktree-lib.sh"

usage() {
  echo "Usage: worktree-remove.sh <path-or-name> [--delete-branch] [--force]" >&2
  exit 1
}

# --- Argument parsing ---
TARGET=""
DELETE_BRANCH=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-branch) DELETE_BRANCH=true; shift ;;
    --force) FORCE=true; shift ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[[ -z "$TARGET" ]] && usage

# --- Validate git repo ---
git_root >/dev/null || { echo "Error: not inside a git repository." >&2; exit 1; }

# --- Resolve path ---
WT_PATH=""
if [[ "$TARGET" == /* ]]; then
  # Absolute path given directly
  WT_PATH="$TARGET"
else
  # Treat as slug: look up in base dir
  BASE_DIR=$(worktree_base_dir)
  WT_PATH="${BASE_DIR}/${TARGET}"
fi

# Verify it's a registered worktree
FOUND=false
while IFS=$'\t' read -r wt_path _branch _hash; do
  if [[ "$wt_path" == "$WT_PATH" ]]; then
    FOUND=true
    break
  fi
done < <(list_worktrees)

if [[ "$FOUND" == false ]]; then
  # Maybe path doesn't exist at all vs. not registered
  if [[ ! -d "$WT_PATH" ]]; then
    echo "Error: no worktree found at: $WT_PATH" >&2
  else
    echo "Error: '$WT_PATH' exists but is not a registered git worktree." >&2
  fi
  exit 1
fi

# --- Get branch before removing (for optional delete) ---
BRANCH=$(branch_for_worktree "$WT_PATH")

# --- Remove worktree ---
if [[ "$FORCE" == true ]]; then
  git worktree remove --force "$WT_PATH"
else
  git worktree remove "$WT_PATH"
fi

echo "✓ Worktree removed: $WT_PATH"

# --- Optionally delete branch ---
if [[ "$DELETE_BRANCH" == true && -n "$BRANCH" && "$BRANCH" != "detached" ]]; then
  if git branch -d "$BRANCH" 2>/dev/null; then
    echo "✓ Branch deleted: $BRANCH"
  else
    echo "! Branch '$BRANCH' has unmerged changes — not deleted." >&2
    echo "  Use 'git branch -D $BRANCH' to force-delete." >&2
  fi
fi

# --- Prune stale metadata ---
git worktree prune 2>/dev/null || true
