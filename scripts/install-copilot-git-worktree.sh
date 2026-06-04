#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AGENT_TOOLKIT_REPO_URL:-https://github.com/St0nefish/agent-toolkit.git}"
REF="${AGENT_TOOLKIT_REF:-${1:-master}}"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
SOURCE_TREE="${AGENT_TOOLKIT_SOURCE_DIR:-}"
EXTENSION_NAME="git-worktree"
EXTENSION_SUBDIR=".github/extensions/${EXTENSION_NAME}"
EXTENSIONS_DIR="${COPILOT_HOME}/extensions"
TARGET_DIR="${EXTENSIONS_DIR}/${EXTENSION_NAME}"
CACHE_DIR="${COPILOT_HOME}/.agent-toolkit-cache/${EXTENSION_NAME}"
REPO_CACHE_DIR="${CACHE_DIR}/repo"

copy_extension() {
  local source_root="$1"

  if [[ ! -f "${source_root}/${EXTENSION_SUBDIR}/extension.mjs" ]]; then
    echo "Extension source not found at ${source_root}/${EXTENSION_SUBDIR}" >&2
    exit 1
  fi

  mkdir -p "$EXTENSIONS_DIR"
  rm -rf "$TARGET_DIR"
  cp -R "${source_root}/${EXTENSION_SUBDIR}" "$TARGET_DIR"
  find "$TARGET_DIR" -type f -name '*.sh' -exec chmod +x {} +
}

update_cache_from_git() {
  mkdir -p "$CACHE_DIR"

  if [[ ! -d "$REPO_CACHE_DIR/.git" ]]; then
    git clone --filter=blob:none --depth 1 --sparse "$REPO_URL" "$REPO_CACHE_DIR" >/dev/null 2>&1
  else
    git -C "$REPO_CACHE_DIR" remote set-url origin "$REPO_URL"
  fi

  git -C "$REPO_CACHE_DIR" sparse-checkout set --no-cone "$EXTENSION_SUBDIR"
  git -C "$REPO_CACHE_DIR" fetch --depth 1 origin "$REF" >/dev/null 2>&1
  git -C "$REPO_CACHE_DIR" checkout --force FETCH_HEAD >/dev/null 2>&1
  git -C "$REPO_CACHE_DIR" clean -fdx >/dev/null 2>&1
}

if [[ -n "$SOURCE_TREE" ]]; then
  copy_extension "$SOURCE_TREE"
  SOURCE_DESC="$SOURCE_TREE"
else
  update_cache_from_git
  copy_extension "$REPO_CACHE_DIR"
  SOURCE_DESC="$REPO_URL@$REF"
fi

cat <<MSG
Installed ${EXTENSION_NAME} to ${TARGET_DIR}
Source: ${SOURCE_DESC}

Next step: run /clear in Copilot CLI to reload extensions in active sessions.
MSG
