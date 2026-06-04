#!/usr/bin/env bash
# worktree-lib.sh — Shared functions for the git-worktree extension scripts.
# Source this file from other scripts in the same directory.

# Returns the root of the *current* checkout (the linked worktree path when
# called from inside one).
git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Returns the root of the *main* worktree, even when called from a linked
# worktree. `git worktree list --porcelain` always lists the main worktree
# first.
main_repo_root() {
  git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'
}

# Returns the bare repository name (basename of main repo root).
repo_name() {
  local root
  root=$(main_repo_root) || return 1
  basename "$root"
}

# Returns the base directory where worktrees for this repo are stored.
# Default: <main-repo-root>/.github/worktrees (in-repo; gitignored on first use)
# Override with WORKTREE_BASE_DIR env var.
worktree_base_dir() {
  if [[ -n "${WORKTREE_BASE_DIR:-}" ]]; then
    echo "$WORKTREE_BASE_DIR"
    return 0
  fi
  local root
  root=$(main_repo_root) || return 1
  echo "$root/.github/worktrees"
}

# Convert a branch name to a filesystem-safe directory slug.
# Replaces / and other non-alphanumeric chars (except - and _) with -.
# Collapses consecutive - and trims leading/trailing -.
slug_from_branch() {
  local branch="$1"
  echo "$branch" |
    tr '/' '-' |
    sed 's/[^a-zA-Z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# List all linked worktrees (excludes the main worktree).
# Output format: <path>\t<branch>\t<hash>
# Branch is "detached" if HEAD is detached.
list_worktrees() {
  local path="" branch="" hash="" seen_count=0

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        # Flush the previous block, skipping the first (main worktree, seen_count=1 at flush time)
        if [[ -n "$path" && "$seen_count" -gt 1 ]]; then
          printf '%s\t%s\t%s\n' "$path" "${branch:-unknown}" "${hash:-unknown}"
        fi
        path="${line#worktree }"
        branch=""
        hash=""
        ((seen_count++)) || true
        ;;
      "HEAD "*)
        hash="${line#HEAD }"
        ;;
      "branch "*)
        branch="${line#branch refs/heads/}"
        ;;
      "detached")
        branch="detached"
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)

  # Flush last block if it's a linked worktree (seen_count > 1 means we saw at least 2 blocks)
  if [[ -n "$path" && "$seen_count" -gt 1 ]]; then
    printf '%s\t%s\t%s\n' "$path" "${branch:-unknown}" "${hash:-unknown}"
  fi
}

# Returns 0 if <target> is within any registered worktree path, 1 otherwise.
# Checks if target starts with a known worktree path (prefix match).
is_worktree_path() {
  local target="$1"
  [[ -z "$target" ]] && return 1

  local wt_path
  while IFS=$'\t' read -r wt_path _branch _hash; do
    [[ -z "$wt_path" ]] && continue
    if [[ "$target" == "$wt_path" || "$target" == "$wt_path/"* ]]; then
      return 0
    fi
  done < <(list_worktrees)

  return 1
}

# Returns the branch currently checked out in a worktree at <path>.
branch_for_worktree() {
  local wt_path="$1"
  local path="" branch=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*) branch="${line#branch refs/heads/}" ;;
      "")
        if [[ "$path" == "$wt_path" ]]; then
          echo "$branch"
          return 0
        fi
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
}
