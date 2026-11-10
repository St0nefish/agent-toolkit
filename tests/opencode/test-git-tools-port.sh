#!/usr/bin/env bash
# test-git-tools-port.sh — the OpenCode git-tools port stays faithful to the
# Claude original: same procedure content, OpenCode-only edits (skill-relative
# script paths, no Claude frontmatter/vars), and working vendored scripts.
#
# Usage: bash tests/opencode/test-git-tools-port.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."
CLAUDE="$REPO/plugins-claude/git-tools"
OC="$REPO/plugins-opencode/git-tools"

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
t2() {
	local label="$1"
	shift
	if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then return; fi
	if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "assertion failed"; fi
}

# --- vendored scripts present, executable, byte-identical to canonical ------
for skill in git-wait ship; do
	v="$OC/skills/$skill/scripts/git-wait"
	t2 "$skill vendors git-wait" test -x "$v"
	t2 "$skill copy matches utils/git-wait" cmp -s "$REPO/utils/git-wait" "$v"
done

# --- no Claude harness leakage in the port ----------------------------------
t2 "no CLAUDE_PLUGIN_ROOT in port" sh -c "! grep -rq 'CLAUDE_PLUGIN_ROOT' '$OC'"
t2 "no allowed-tools frontmatter in port" sh -c "! grep -rq 'allowed-tools:' '$OC/skills'"
t2 "no \$ARGUMENTS in skill bodies" sh -c "! grep -rq 'ARGUMENTS' '$OC/skills'"

# --- frontmatter: name + description on both skills --------------------------
for skill in git-wait ship; do
	f="$OC/skills/$skill/SKILL.md"
	t2 "$skill has name" sh -c "awk '/^---\$/{n++; next} n==1' '$f' | grep -q '^name: '"
	t2 "$skill has description" sh -c "awk '/^---\$/{n++; next} n==1' '$f' | grep -q '^description: '"
done

# --- content fidelity vs the Claude original ---------------------------------
# After normalizing the intended edits (script paths, frontmatter, argument
# wording), the ported bodies must match the originals — catches accidental
# content loss during the port.
for skill in git-wait ship; do
	c="$CLAUDE/skills/$skill/SKILL.md"
	o="$OC/skills/$skill/SKILL.md"
	# strip frontmatter from both, then compare bodies after path normalization
	awk '/^---$/{n++; next} n>=2' "$c" >"$TMP/c.body"
	awk '/^---$/{n++; next} n>=2' "$o" |
		sed -E -e 's#bash scripts/git-wait#bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait#g' \
			-e '/^All `scripts\/\.\.\.` paths below/,/^\(provided when the skill loads\)\.$/d' \
			-e 's#If the user explicitly invokes `/ship`#If the user explicitly invokes `/git-tools:ship`#' \
			>"$TMP/o.body"
	if [[ "$skill" == "git-wait" ]]; then
		# git-wait body must be otherwise identical
		if diff -q -B "$TMP/c.body" "$TMP/o.body" >/dev/null; then
			pass "git-wait body matches Claude original (modulo intended edits)"
		else
			fail "git-wait body matches Claude original (modulo intended edits)" "$(diff "$TMP/c.body" "$TMP/o.body" | head -5)"
		fi
	fi
done

# ship: full procedure intact — all numbered steps present
for step in "### 0. Read state" "### 1. Detect platform" "### 2. Stage and commit" \
	"### 3. Ensure feature branch" "### 4. Push" "### 5. Create PR" \
	"### 6. Watch CI" "### 7. Wait for merge" "### 8. Watch the post-merge run" \
	"### 9. Return to default branch"; do
	t2 "ship has step: $step" grep -qF "$step" "$OC/skills/ship/SKILL.md"
done

# gh-vs-tea command map survived
t2 "ship/git-wait keep the gh-vs-tea map" grep -qF "tea pulls" "$OC/skills/git-wait/SKILL.md"

# --- /ship command door -------------------------------------------------------
t2 "ship command exists" test -s "$OC/commands/ship.md"
t2 "ship command points at the skill" grep -qi "ship.*skill" "$OC/commands/ship.md"
t2 "ship command passes \$ARGUMENTS through" grep -q '\$ARGUMENTS' "$OC/commands/ship.md"

# --- config snippet -----------------------------------------------------------
t2 "config snippet has skills array" sh -c "node -e '
	const s = require(\"fs\").readFileSync(\"$OC/opencode.jsonc\", \"utf8\")
		.replace(/^\s*\/\/.*\$/gm, \"\").replace(/,(\s*[}\]])/g, \"\$1\");
	const c = JSON.parse(s);
	if (!Array.isArray(c.skills) || c.skills.length === 0) process.exit(1);
	if (!c.commands || !c.commands.ship || !c.commands.ship.template) process.exit(1);
'"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
