#!/usr/bin/env bash
# worktree-list.sh — List all linked git worktrees for the current repo.
#
# Usage: worktree-list.sh
#
# Displays a formatted table of all linked worktrees (excludes the main checkout).

set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=worktree-lib.sh
source "$SCRIPTS_DIR/worktree-lib.sh"

# --- Validate git repo ---
git_root >/dev/null || { echo "Error: not inside a git repository." >&2; exit 1; }

# --- Collect worktrees ---
mapfile -t WORKTREES < <(list_worktrees)

if [[ ${#WORKTREES[@]} -eq 0 ]]; then
  echo "No linked worktrees found."
  echo ""
  echo "Create one with: git worktree add .github/worktrees/<slug> -b <branch-name>"
  exit 0
fi

# --- Print header ---
printf '%-50s  %-30s  %s\n' "PATH" "BRANCH" "STATUS"
printf '%s\n' "$(printf '%0.s-' {1..90})"

# --- Print each worktree ---
for entry in "${WORKTREES[@]}"; do
  IFS=$'\t' read -r wt_path branch _hash <<<"$entry"

  # Check if worktree directory still exists
  if [[ ! -d "$wt_path" ]]; then
    status="MISSING (run: git worktree prune)"
  else
    # Check for dirty state
    dirty_count=$(git -C "$wt_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$dirty_count" -eq 0 ]]; then
      status="clean"
    else
      status="${dirty_count} modified"
    fi
  fi

  printf '%-50s  %-30s  %s\n' "$wt_path" "$branch" "$status"
done
