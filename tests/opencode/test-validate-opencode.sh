#!/usr/bin/env bash
# test-validate-opencode.sh — the OpenCode structural validator itself.
#
# Copies .github/scripts/validate-opencode.sh into a sandbox repo layout and
# feeds it a clean fixture tree (must pass) and a dirty one (must fail with
# each failure class named). Also asserts the real plugins-opencode/ tree
# passes the real validator.
#
# Usage: bash tests/opencode/test-validate-opencode.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."
VALIDATOR="$REPO/.github/scripts/validate-opencode.sh"

PASS=0
FAIL=0
FILTER="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() {
	printf "  \033[32m✓\033[0m %s\n" "$1"
	((PASS++)) || true
}
fail() {
	printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
	((FAIL++)) || true
}

RC=0
OUT=""
run() {
	RC=0
	OUT=$("$@" 2>&1) || RC=$?
}

# expect_output <label> <pattern>
expect_output() {
	if [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; then return; fi
	if echo "$OUT" | grep -q "$2"; then pass "$1"; else fail "$1" "no match for: $2"; fi
}

# --- build a clean fixture repo --------------------------------------------
mk_clean() {
	local S="$1"
	mkdir -p "$S/.github/scripts" "$S/plugins-opencode/inbox/src" \
		"$S/plugins-opencode/inbox/scripts" "$S/plugins-opencode/inbox/skills/show" \
		"$S/plugins-opencode/inbox/commands" "$S/plugins-opencode/session/src"
	cp "$VALIDATOR" "$S/.github/scripts/"
	cat >"$S/plugins-opencode/inbox/package.json" <<'EOF'
{
  "name": "opencode-agent-toolkit-inbox",
  "version": "0.1.0",
  "type": "module",
  "exports": { ".": "./src/index.ts" }
}
EOF
	cat >"$S/plugins-opencode/session/package.json" <<'EOF'
{
  "name": "opencode-agent-toolkit-session",
  "version": "0.1.0",
  "type": "module",
  "exports": { ".": "./src/index.ts" }
}
EOF
	echo 'export default {}' >"$S/plugins-opencode/session/src/index.ts"
	echo 'export default {}' >"$S/plugins-opencode/inbox/src/index.ts"
	printf -- '---\nname: Show\ndescription: Show open items\n---\n\nList the inbox.\n' \
		>"$S/plugins-opencode/inbox/skills/show/SKILL.md"
	printf -- '---\ndescription: show inbox\n---\n\n!`echo hi`\n' \
		>"$S/plugins-opencode/inbox/commands/show.md"
	printf '{\n  // a comment\n  "formatter": true,\n}\n' >"$S/plugins-opencode/inbox/opencode.jsonc"
	printf '#!/usr/bin/env bash\necho hi\n' >"$S/plugins-opencode/inbox/scripts/inbox"
	chmod +x "$S/plugins-opencode/inbox/scripts/inbox"
}

# --- clean fixture passes ----------------------------------------------------
S="$TMP/clean"
mk_clean "$S"
run bash "$S/.github/scripts/validate-opencode.sh"
if [[ -z "$FILTER" ]] || echo "clean fixture passes" | grep -qi "$FILTER"; then
	if [[ $RC -eq 0 ]]; then pass "clean fixture passes"; else fail "clean fixture passes" "exit=$RC: $OUT"; fi
fi

# --- dirty fixture fails, naming every failure class ------------------------
S="$TMP/dirty"
mk_clean "$S"
P="$S/plugins-opencode/inbox"
echo '{ broken' >"$P/broken.json"
cat >"$P/package.json" <<'EOF'
{
  "name": "opencode-agent-toolkit-inbox",
  "version": "0.1.0",
  "type": "module",
  "exports": { ".": "./src/missing.ts" }
}
EOF
printf -- '---\nname: NoDesc\n---\n\nbody\n' >"$P/skills/show/SKILL.md"
printf -- '---\ndescription: empty body\n---\n\n' >"$P/commands/show.md"
printf 'uses ${CLAUDE_PLUGIN_ROOT}/scripts/inbox\n' >"$P/leak.md"
chmod -x "$P/scripts/inbox"
run bash "$S/.github/scripts/validate-opencode.sh"
if [[ $RC -ne 0 ]]; then pass "dirty fixture fails"; else fail "dirty fixture fails" "exit=0: $OUT"; fi
expect_output "names invalid JSON" "broken.json — invalid JSON"
expect_output "names missing export target" "export target missing"
expect_output "names missing skill description" "missing required field: description"
expect_output "names empty command body" "empty command body"
expect_output "names Claude leakage" "Claude var in OpenCode tree"
expect_output "names non-executable script" "not executable"

# --- real tree passes the real validator --------------------------------------
run bash "$VALIDATOR"
if [[ -z "$FILTER" ]] || echo "real tree passes" | grep -qi "$FILTER"; then
	if [[ $RC -eq 0 ]]; then pass "real plugins-opencode/ passes validator"; else fail "real plugins-opencode/ passes validator" "exit=$RC: $OUT"; fi
fi

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
