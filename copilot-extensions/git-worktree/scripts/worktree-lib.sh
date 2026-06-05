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

# Returns 0 if the local branch exists, 1 otherwise.
branch_exists() {
  git rev-parse --verify "refs/heads/$1" >/dev/null 2>&1
}

# Returns 0 if the ref resolves to a commit, 1 otherwise.
ref_exists() {
  git rev-parse --verify "$1^{commit}" >/dev/null 2>&1
}

# Returns the current branch name, or nothing when HEAD is detached.
current_branch() {
  git branch --show-current 2>/dev/null
}

# Returns the best default base ref for new work:
# - prefer origin/HEAD (for example origin/main)
# - then origin/main or origin/master if present
# - then local main or master
default_base_ref() {
  local ref=""

  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$ref" ]]; then
    echo "$ref"
    return 0
  fi

  for ref in origin/main origin/master main master; do
    if ref_exists "$ref"; then
      echo "$ref"
      return 0
    fi
  done

  return 1
}

# List all worktrees, including the main worktree.
# Output format: <path>\t<branch>\t<hash>
# Branch is "detached" if HEAD is detached.
worktree_records() {
  local path="" branch="" hash=""

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        if [[ -n "$path" ]]; then
          printf '%s\t%s\t%s\n' "$path" "${branch:-unknown}" "${hash:-unknown}"
        fi
        path="${line#worktree }"
        branch=""
        hash=""
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
      "")
        if [[ -n "$path" ]]; then
          printf '%s\t%s\t%s\n' "$path" "${branch:-unknown}" "${hash:-unknown}"
        fi
        path=""
        branch=""
        hash=""
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null; printf '\n')
}

# List all linked worktrees (excludes the main worktree).
# Output format: <path>\t<branch>\t<hash>
list_worktrees() {
  local path="" branch="" hash=""
  local first=true

  while IFS=$'\t' read -r path branch hash; do
    if [[ "$first" == true ]]; then
      first=false
      continue
    fi
    printf '%s\t%s\t%s\n' "$path" "$branch" "$hash"
  done < <(worktree_records)
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
  local path="" branch="" hash=""

  while IFS=$'\t' read -r path branch hash; do
    if [[ "$path" == "$wt_path" ]]; then
      echo "$branch"
      return 0
    fi
  done < <(worktree_records)
}

# Returns the worktree path currently using <branch>, if any.
worktree_path_for_branch() {
  local target_branch="$1"
  local path="" branch="" hash=""

  while IFS=$'\t' read -r path branch hash; do
    if [[ "$branch" == "$target_branch" ]]; then
      echo "$path"
      return 0
    fi
  done < <(worktree_records)
}
