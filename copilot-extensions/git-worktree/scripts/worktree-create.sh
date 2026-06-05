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
# from <base-branch>. Without --from, new branches default to the current
# branch; when HEAD is detached they default to the repo's default branch.

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

if [[ -z "$SLUG" ]]; then
  echo "Error: branch name '$BRANCH' does not produce a usable worktree slug." >&2
  exit 1
fi

if [[ -e "$WT_PATH" ]]; then
  echo "Error: target worktree path already exists: $WT_PATH" >&2
  exit 1
fi

if EXISTING_PATH=$(worktree_path_for_branch "$BRANCH" 2>/dev/null); [[ -n "$EXISTING_PATH" ]]; then
  echo "Error: branch '$BRANCH' is already checked out in another worktree: $EXISTING_PATH" >&2
  exit 1
fi

BASE_REF=""
BASE_REASON=""

if ! branch_exists "$BRANCH"; then
  if [[ -n "$FROM_BRANCH" ]]; then
    BASE_REF="$FROM_BRANCH"
    BASE_REASON="explicit base"
  else
    CURRENT_BRANCH=$(current_branch || true)
    if [[ -n "$CURRENT_BRANCH" ]]; then
      BASE_REF="$CURRENT_BRANCH"
      BASE_REASON="current branch"
    else
      BASE_REF=$(default_base_ref || true)
      if [[ -z "$BASE_REF" ]]; then
        echo "Error: HEAD is detached and no default branch could be resolved. Re-run with --from <base-branch>." >&2
        exit 1
      fi
      BASE_REASON="default branch"
    fi
  fi

  if ! ref_exists "$BASE_REF"; then
    echo "Error: base ref '$BASE_REF' does not exist." >&2
    exit 1
  fi
fi

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
  git worktree add "$WT_PATH" "$BRANCH"
  HEAD_SHA=$(git -C "$WT_PATH" rev-parse --short HEAD 2>/dev/null || true)
  echo "Created linked worktree for branch $BRANCH."
  echo "Path: $WT_PATH"
  [[ -n "$HEAD_SHA" ]] && echo "HEAD: $HEAD_SHA"
else
  git worktree add "$WT_PATH" -b "$BRANCH" "$BASE_REF"
  HEAD_SHA=$(git -C "$WT_PATH" rev-parse --short HEAD 2>/dev/null || true)
  echo "Created linked worktree for branch $BRANCH."
  echo "Path: $WT_PATH"
  echo "Base: $BASE_REASON $BASE_REF"
  [[ -n "$HEAD_SHA" ]] && echo "HEAD: $HEAD_SHA"
fi

echo "Use it with: cd $WT_PATH"
