#!/usr/bin/env bash
set -euo pipefail

COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
PERMISSION_LOCATION="${1:-}"
EXTENSION_NAME="git-worktree"
PERMISSIONS_FILE="${COPILOT_HOME}/permissions-config.json"

detect_permission_location() {
  if [[ -n "$PERMISSION_LOCATION" ]]; then
    realpath "$PERMISSION_LOCATION"
    return
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd -P
  fi
}

seed_permissions() {
  local location_key="$1"
  local tmp_file

  mkdir -p "$COPILOT_HOME"
  if [[ ! -f "$PERMISSIONS_FILE" ]]; then
    printf '{\n  "locations": {}\n}\n' >"$PERMISSIONS_FILE"
  fi

  tmp_file=$(mktemp)
  jq \
    --arg loc "$location_key" \
    --arg ext "user:${EXTENSION_NAME}" \
    --argjson tools '[
      "sf_git_worktree_status",
      "sf_git_worktree_create",
      "sf_git_worktree_remove",
      "sf_git_worktree_suggest"
    ]' \
    '
      .locations = (.locations // {}) |
      .locations[$loc] = (.locations[$loc] // {}) |
      .locations[$loc].tool_approvals = (.locations[$loc].tool_approvals // []) |
      if any(.locations[$loc].tool_approvals[]?; .kind == "extension-permission-access" and .extensionName == $ext) then
        .
      else
        .locations[$loc].tool_approvals += [{kind: "extension-permission-access", extensionName: $ext}]
      end |
      reduce $tools[] as $tool (.;
        if any(.locations[$loc].tool_approvals[]?; .kind == "custom-tool" and .toolName == $tool) then
          .
        else
          .locations[$loc].tool_approvals += [{kind: "custom-tool", toolName: $tool}]
        end
      )
    ' \
    "$PERMISSIONS_FILE" >"$tmp_file"
  mv "$tmp_file" "$PERMISSIONS_FILE"
}

LOCATION_KEY="$(detect_permission_location)"
seed_permissions "$LOCATION_KEY"

cat <<MSG
Seeded git-worktree approvals for: ${LOCATION_KEY}
Config: ${PERMISSIONS_FILE}

Approvals added:
- extension-permission-access: user:git-worktree
- custom-tool: sf_git_worktree_status
- custom-tool: sf_git_worktree_create
- custom-tool: sf_git_worktree_remove
- custom-tool: sf_git_worktree_suggest
MSG
