#!/usr/bin/env bash
# Test the supervisor's pure root, identity, state, decision, and lock logic.
# It deliberately does not invoke main(), systemd, Serena, or network listeners.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$SCRIPT_DIR/../../plugins-claude/agentic-ide/scripts/serena-shared-bridge"
COPILOT_PLUGIN="$SCRIPT_DIR/../../plugins-copilot/agentic-ide"

# shellcheck source=/dev/null
source "$BRIDGE"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() {
  printf "  \033[32m+\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31mx\033[0m %s\n" "$1"
  ((FAIL++)) || true
}

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, got $actual)"
  fi
}

assert_fails() {
  local label="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    fail "$label (unexpected success)"
  else
    pass "$label"
  fi
}

assert_file_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"

  if grep -Fqx -- "$needle" "$file"; then
    pass "$label"
  else
    fail "$label (missing $needle)"
  fi
}

echo "-- Git root resolution --"
repository="$TMP/repository"
mkdir -p "$repository/nested/path" "$TMP/outside"
(
  cd -- "$repository"
  git init --quiet
)
assert_equal "resolves the absolute worktree root" \
  "$(resolve_project_root "$repository/nested/path")" "$repository"
assert_fails "rejects a directory outside Git" resolve_project_root "$TMP/outside"
assert_equal "finds the active worktree through a plugin child's parent" \
  "$(
    cd -- "$repository"
    bash -c 'cd -- "$1/outside"; source "$2"; resolve_project_root' \
      _ "$TMP" "$BRIDGE"
  )" "$repository"

echo "-- Worktree identity and paths --"
identity=$(root_identity "$repository")
assert_equal "identity is deterministic" "$(root_identity "$repository")" "$identity"
assert_fails "identity changes for another absolute worktree path" \
  test "$(root_identity "$repository/other")" = "$identity"
assert_equal "runtime path uses XDG runtime directory and user id" \
  "$(XDG_RUNTIME_DIR="$TMP/runtime-base" runtime_state_dir)" \
  "$TMP/runtime-base/$RUNTIME_PREFIX-$(id -u)"
assert_equal "state filename is derived only from the identity" \
  "$(state_file_for "$TMP/runtime" "$identity")" "$TMP/runtime/$identity.state"
assert_equal "unit name is injection-safe and deterministic" \
  "$(unit_name_for "$identity")" "$RUNTIME_PREFIX-$identity.service"

echo "-- Copilot plugin registration --"
assert_equal "uses the Agent Plugins 1.0 manifest" \
  "$(jq -r '."$schema"' "$COPILOT_PLUGIN/plugin.json")" \
  "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
assert_equal "declares a legacy Copilot MCP fallback" \
  "$(jq -r '.mcpServers' "$COPILOT_PLUGIN/.claude-plugin/plugin.json")" \
  "./mcp.json"
assert_equal "registers the shared bridge as Serena" \
  "$(jq -r '.mcpServers.serena.command' "$COPILOT_PLUGIN/mcp.json")" bash
assert_equal "uses the documented plugin-root expansion" \
  "$(jq -r '.mcpServers.serena.args[0]' "$COPILOT_PLUGIN/mcp.json")" \
  '${PLUGIN_ROOT}/scripts/serena-shared-bridge'
assert_equal "inherits Copilot's project working directory" \
  "$(jq -r '.mcpServers.serena.cwd // empty' "$COPILOT_PLUGIN/mcp.json")" ""
[[ -f "$COPILOT_PLUGIN/com.github.copilot/commands/setup.md" ]] &&
  pass "preserves the Copilot setup command" ||
  fail "preserves the Copilot setup command"
[[ -f "$COPILOT_PLUGIN/com.github.copilot/agents/serena-explorer.agent.md" ]] &&
  pass "preserves the Serena explorer agent" ||
  fail "preserves the Serena explorer agent"

echo "-- Port and persisted state validation --"
valid_port 1024 && pass "accepts lower valid port" || fail "accepts lower valid port"
valid_port 65535 && pass "accepts upper valid port" || fail "accepts upper valid port"
assert_fails "rejects privileged port" valid_port 80
assert_fails "rejects non-numeric port" valid_port '1234;command'
assert_fails "rejects out-of-range port" valid_port 65536

state_dir="$TMP/runtime"
mkdir -m 700 "$state_dir"
state_file=$(state_file_for "$state_dir" "$identity")
write_state "$state_dir" "$state_file" "$identity" 43123
read_state "$state_file" "$identity"
assert_equal "reads a valid persisted port" "$STATE_PORT" 43123

printf '%s\ninvalid\n' "$identity" >"$state_file"
chmod 600 "$state_file"
assert_fails "rejects invalid persisted port" read_state "$state_file" "$identity"

printf '%s\n43123\nextra\n' "$identity" >"$state_file"
chmod 600 "$state_file"
assert_fails "rejects state with an unexpected field" read_state "$state_file" "$identity"

printf '%s\n43123\n' "0000000000000000000000000000000000000000000000000000000000000000" >"$state_file"
chmod 600 "$state_file"
assert_fails "rejects state belonging to another worktree" read_state "$state_file" "$identity"

printf '%s\n43123\n' "$identity" >"$state_file"
chmod 644 "$state_file"
assert_fails "rejects group-readable persisted state" read_state "$state_file" "$identity"

ln -sf "$state_file" "$state_dir/symlinked.state"
assert_fails "rejects symbolic-link persisted state" \
  read_state "$state_dir/symlinked.state" "$identity"

echo "-- Duplicate-prevention decisions and lock --"
assert_equal "ready backend is reused" "$(backend_action true false)" reuse
assert_equal "loaded but unready backend is replaced" "$(backend_action false true)" replace
assert_equal "missing backend is started" "$(backend_action false false)" start

lock_file=$(lock_file_for "$state_dir" "$identity")
exec {lock_fd}>"$lock_file"
flock "$lock_fd"
if (
  exec {contender_fd}>"$lock_file"
  flock -n "$contender_fd"
); then
  fail "second bridge cannot acquire the per-root lock"
else
  pass "second bridge cannot acquire the per-root lock"
fi
flock -u "$lock_fd"
exec {lock_fd}>&-

echo "-- Serena installation and unit arguments --"
mock_bin="$TMP/mock-bin"
install_bin="$TMP/uv-tool-bin"
mkdir -p "$mock_bin" "$install_bin" "$TMP/home/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$mock_bin/serena"
chmod 700 "$mock_bin/serena"

resolved=$(HOME="$TMP/home" PATH="$mock_bin:/usr/bin:/bin" UV_TOOL_BIN_DIR="" resolve_serena_executable)
assert_equal "resolves PATH executable to an absolute path" "$resolved" "$mock_bin/serena"

UV_ARGS="$TMP/uv.args"
uv() {
  printf '%s\n' "$@" >"$UV_ARGS"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$UV_TOOL_BIN_DIR/serena"
  chmod 700 "$UV_TOOL_BIN_DIR/serena"
}

SERENA_EXECUTABLE=""
HOME="$TMP/home" PATH="$TMP/empty:/usr/bin:/bin" UV_TOOL_BIN_DIR="$install_bin" ensure_serena
assert_equal "installs and resolves Serena from uv tool bin" "$SERENA_EXECUTABLE" "$install_bin/serena"
assert_file_contains "uses the documented uv tool install command" "tool" "$UV_ARGS"
assert_file_contains "uses the documented Serena source" "--from" "$UV_ARGS"
assert_file_contains "installs the Serena command" "serena" "$UV_ARGS"

uv() {
  return 1
}

rm -f -- "$install_bin/serena"
if HOME="$TMP/home" PATH="$TMP/empty:/usr/bin:/bin" UV_TOOL_BIN_DIR="$install_bin" ensure_serena \
  2>"$TMP/install-error"; then
  fail "reports automatic installation failure"
else
  assert_file_contains "reports automatic installation failure" \
    "Automatic Serena installation failed." "$TMP/install-error"
fi

SYSTEMD_ARGS="$TMP/systemd-run.args"
systemd-run() {
  printf '%s\n' "$@" >"$SYSTEMD_ARGS"
}

SERENA_EXECUTABLE="$mock_bin/serena"
start_backend "agentic-ide-serena-test.service" "$repository" 43123
assert_file_contains "passes an absolute Serena executable to systemd" "$mock_bin/serena" "$SYSTEMD_ARGS"
assert_file_contains "passes the fixed MCP server command" "start-mcp-server" "$SYSTEMD_ARGS"
assert_file_contains "passes the absolute worktree as a distinct argument" "$repository" "$SYSTEMD_ARGS"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
exit "$FAIL"
