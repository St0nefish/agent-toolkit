#!/usr/bin/env bash
# test-session-port.sh — the OpenCode session port stays faithful to the
# Claude original. The ported SKILL.md files must equal
# utils/opencode-port.py(Claude original) — so any upstream edit to a Claude
# skill that isn't re-ported (or a mapping bug) fails here. Vendored scripts
# must be byte-identical to utils/; the rendered spine must match what
# sync.sh produces; no Claude-harness leakage anywhere.
#
# Usage: bash tests/opencode/test-session-port.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."
CLAUDE="$REPO/plugins-claude/session"
OC="$REPO/plugins-opencode/session"
PORTER="$REPO/utils/opencode-port.py"

PASS=0
FAIL=0
FILTER="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() {
	printf "  \033[32m✓\x1b[0m %s\n" "$1"
	((PASS++)) || true
}
fail() {
	printf "  \033[31m✗\x1b[0m %s  (%s)\n" "$1" "$2"
	((FAIL++)) || true
}
t2() {
	local label="$1"
	shift
	if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then return; fi
	if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "assertion failed: $*"; fi
}

SKILLS="session-start session-issue session-end session-orchestrate session-summarize"

# --- no Claude harness leakage in the whole opencode session tree ------------
for pat in CLAUDE_PLUGIN_ROOT EnterWorktree ExitWorktree EnterPlanMode AskUserQuestion subagent_type '\$ARGUMENTS' '/session:' '/git-tools:' 'allowed-tools:' Workflow; do
	t2 "no leakage: $pat" sh -c "! grep -rq -- '$pat' '$OC/skills' '$OC/src'"
done

# --- ported skills == porter(Claude original) ---------------------------------
# The porter strips `allowed-tools:` frontmatter lines, applies the harness
# mapping, then applies its $ARGUMENTS rewrites. Reproduce that pipeline here
# from the CURRENT Claude originals: if someone edits a Claude skill and
# forgets to re-run utils/port-session-skills.py, this comparison breaks.
for skill in $SKILLS; do
	src="$CLAUDE/skills/$skill/SKILL.md"
	dst="$OC/skills/$skill/SKILL.md"
	t2 "$skill exists in port" test -s "$dst"
	# frontmatter: name + description present, no allowed-tools
	awk '/^---$/{n++; next} n==1' "$dst" >"$TMP/fm"
	t2 "$skill frontmatter has name" grep -q '^name: ' "$TMP/fm"
	t2 "$skill frontmatter has description" grep -q '^description: ' "$TMP/fm"
	t2 "$skill frontmatter drops allowed-tools" sh -c "! grep -q 'allowed-tools' '$TMP/fm'"
done

# full-file fidelity: run the porter's own pipeline via port-session-skills.py
# in a sandbox (it writes to the real tree; we diff against the committed tree
# instead by rendering each original through the same functions).
python3 - "$REPO" "$TMP" <<'PYEOF'
import re, sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

repo, tmp = Path(sys.argv[1]), Path(sys.argv[2])
spec = spec_from_file_location("psp", repo / "utils" / "port-session-skills.py")
# exec-ing the module would rewrite the tree; instead import its tables only.
src = (repo / "utils" / "port-session-skills.py").read_text()
ns = {}
# grab ARG_REWRITES + strip_frontmatter_line without running the port loop
head = src.split("for skill in SKILLS:")[0]
ns = {"__file__": str(repo / "utils" / "port-session-skills.py")}
exec(compile(head, "port-session-skills.py", "exec"), ns)
render, ARG_REWRITES, strip = ns["render"], ns["ARG_REWRITES"], ns["strip_frontmatter_line"]

for skill in ns["SKILLS"]:
    text = strip((repo / "plugins-claude/session/skills" / skill / "SKILL.md").read_text(), "allowed-tools")
    text = render(text)
    for old, new in ARG_REWRITES.get(skill, []):
        text = text.replace(old, new)
    (tmp / f"{skill}.expected").write_text(text)
PYEOF
for skill in $SKILLS; do
	if diff -q "$TMP/$skill.expected" "$OC/skills/$skill/SKILL.md" >/dev/null 2>&1; then
		pass "$skill matches porter output (up to date)"
	else
		fail "$skill matches porter output (up to date)" "re-run utils/port-session-skills.py — diff: $(diff "$TMP/$skill.expected" "$OC/skills/$skill/SKILL.md" | head -4)"
	fi
done

# --- vendored scripts byte-identical to canonical utils/ ----------------------
declare -A VENDORS=(
	["session-start"]="git-wait branch"
	["session-issue"]="git-wait branch"
	["session-end"]="git-wait sitrep"
	["session-summarize"]="sitrep"
	["session-orchestrate"]="git-wait sitrep"
)
for skill in $SKILLS; do
	for util in ${VENDORS[$skill]}; do
		t2 "$skill vendors $util byte-identical" cmp -s "$REPO/utils/$util" "$OC/skills/$skill/scripts/$util"
	done
done

# --- rendered spine matches sync.sh's rendering of utils/spine.md --------------
for skill in session-start session-issue; do
	python3 "$PORTER" <"$REPO/utils/spine.md" >"$TMP/spine.rendered"
	t2 "$skill spine.md matches opencode-port rendering" cmp -s "$TMP/spine.rendered" "$OC/skills/$skill/reference/spine.md"
done
# and the Claude copy stays byte-identical to the canonical
t2 "claude spine.md byte-identical to utils/spine.md" cmp -s "$REPO/utils/spine.md" "$CLAUDE/reference/spine.md"

# --- harness mapping actually landed in the rendered spine ----------------------
t2 "spine maps EnterWorktree → worktree_create" grep -q "opencode.worktree_create" "$OC/skills/session-start/reference/spine.md"
t2 "spine maps EnterPlanMode → plan agent" sh -c "! grep -q 'EnterPlanMode' '$OC/skills/session-start/reference/spine.md'"
t2 "spine maps rename-session → session_rename" grep -q "session_rename" "$OC/skills/session-start/reference/spine.md"
t2 "spine keeps git-wait usage (skill-relative)" grep -q "bash scripts/git-wait" "$OC/skills/session-start/reference/spine.md"

# --- orchestrate skill points at the tool, not the Workflow script --------------
t2 "orchestrate dispatches orchestrate_build" grep -q "orchestrate_build" "$OC/skills/session-orchestrate/SKILL.md"
t2 "orchestrate has no workflow-script path" sh -c "! grep -q 'orchestrate-build.workflow.js' '$OC/skills/session-orchestrate/SKILL.md'"
# all seven phases survived the port
for phase in "Phase 1" "Phase 2" "Phase 3" "Phase 4" "Phase 5" "Phase 6" "Phase 7"; do
	t2 "orchestrate has $phase" grep -q "$phase" "$OC/skills/session-orchestrate/SKILL.md"
done

# --- plugin package + sources ------------------------------------------------------
t2 "package.json exports src/index.ts" sh -c "node -e '
	const p = require(\"$OC/package.json\");
	if (p.type !== \"module\") process.exit(1);
	if (!p.exports || !p.exports[\".\"] || !p.exports[\".\"].includes(\"src/index.ts\")) process.exit(1);
'"
t2 "orchestrate-core.ts exists" test -s "$OC/src/orchestrate-core.ts"
t2 "index.ts registers orchestrate_build" grep -q '"orchestrate_build"' "$OC/src/index.ts"
t2 "index.ts registers the five door commands" sh -c "grep -q 'session-start.*session-issue.*session-end.*session-orchestrate.*session-summarize' '$OC/src/index.ts'"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
