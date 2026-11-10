#!/usr/bin/env bash
# test-sync.sh — target-aware vendoring in utils/sync.sh.
#
# Builds a sandbox repo (fake utils/ + plugin dirs for both targets), then
# exercises sync, --check cleanliness, and drift detection on each target.
# Never touches the real plugins-* trees.
#
# Usage: bash tests/opencode/test-sync.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."

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
# check <label> <expected: "0" or "nonzero"> <actual-exit-code> [detail]
check() {
	if [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; then return; fi
	local ok
	if [[ "$2" == "0" ]]; then
		[[ "$3" -eq 0 ]] && ok=1 || ok=0
	else
		[[ "$3" -ne 0 ]] && ok=1 || ok=0
	fi
	if [[ $ok -eq 1 ]]; then pass "$1"; else fail "$1" "exit=$3 ${4:-}"; fi
}

# run <cmd...> — runs possibly-failing command, sets RC/OUT/ERR
RC=0
OUT=""
ERR=""
run() {
	RC=0
	OUT=$("$@" 2>"$TMP/stderr") || RC=$?
	ERR=$(cat "$TMP/stderr")
}

# --- sandbox ---------------------------------------------------------------
# Mirror the real manifest's plugin dirs so the real sync.sh runs unmodified.
S="$TMP/repo"
mkdir -p "$S/utils"
cp "$REPO/utils/sync.sh" "$S/utils/"
cp "$REPO/utils/opencode-port.py" "$S/utils/"
for util in inbox git-wait branch sitrep spine.md hook-compat.sh detect-schema.sh validate-frontmatter.sh; do
	cp "$REPO/utils/$util" "$S/utils/"
done
for p in format-on-save git-tools kb-capture inbox notify-on-stop session; do
	mkdir -p "$S/plugins-claude/$p"
done
for p in git-tools/skills/git-wait git-tools/skills/ship inbox \
	session/skills/session-start session/skills/session-issue session/skills/session-end \
	session/skills/session-summarize session/skills/session-orchestrate; do
	mkdir -p "$S/plugins-opencode/$p"
done

sync() { bash "$S/utils/sync.sh" "$@"; }

# --- sync populates both targets -------------------------------------------
run sync
check "sync exits 0" 0 "$RC" "$OUT$ERR"
run cmp -s "$S/utils/inbox" "$S/plugins-claude/inbox/scripts/inbox"
check "claude inbox vendored" 0 "$RC"
run cmp -s "$S/utils/git-wait" "$S/plugins-opencode/git-tools/skills/git-wait/scripts/git-wait"
check "opencode git-wait skill vendored git-wait" 0 "$RC"
run cmp -s "$S/utils/git-wait" "$S/plugins-opencode/git-tools/skills/ship/scripts/git-wait"
check "opencode ship skill vendored git-wait" 0 "$RC"
run test ! -e "$S/plugins-opencode/git-tools/skills/git-wait/scripts/branch"
check "opencode git-tools skills do not receive branch (target-aware manifest)" 0 "$RC"
# claude git-tools must NOT receive branch/sitrep (manifest is per-target)
run test ! -e "$S/plugins-claude/git-tools/scripts/branch"
check "claude git-tools does not receive branch (target-aware manifest)" 0 "$RC"

# claude session receives branch + sitrep (canonicalized from its scripts dir)
run cmp -s "$S/utils/branch" "$S/plugins-claude/session/scripts/branch"
check "claude session vendored branch" 0 "$RC"
run cmp -s "$S/utils/sitrep" "$S/plugins-claude/session/scripts/sitrep"
check "claude session vendored sitrep" 0 "$RC"

# util:dir syntax — spine.md lands in reference/, byte-identical for claude
run cmp -s "$S/utils/spine.md" "$S/plugins-claude/session/reference/spine.md"
check "claude session vendored spine.md into reference/ (util:dir)" 0 "$RC"

# markdown for the opencode target is rendered through opencode-port.py:
# harness mapping applied, no Claude leakage, and NOT byte-identical
run cmp -s "$S/utils/spine.md" "$S/plugins-opencode/session/skills/session-start/reference/spine.md"
check "opencode spine.md is rendered (differs from canonical)" nonzero "$RC"
run grep -q "CLAUDE_PLUGIN_ROOT" "$S/plugins-opencode/session/skills/session-start/reference/spine.md"
check "rendered opencode spine.md has no CLAUDE_PLUGIN_ROOT" nonzero "$RC"
run grep -q "opencode.worktree_create" "$S/plugins-opencode/session/skills/session-start/reference/spine.md"
check "rendered opencode spine.md carries the harness mapping" 0 "$RC"
# nested manifest keys vendor into each skill's own dir
run cmp -s "$S/utils/git-wait" "$S/plugins-opencode/session/skills/session-start/scripts/git-wait"
check "session-start skill vendored git-wait (nested key)" 0 "$RC"
run test ! -e "$S/plugins-opencode/session/scripts/git-wait"
check "session plugin root no longer receives scripts (moved to skills)" 0 "$RC"

# --- --check clean after sync ------------------------------------------------
run sync --check
check "--check clean after sync" 0 "$RC" "$OUT$ERR"

# --- drift on the claude target is detected ----------------------------------
echo "# tampered" >>"$S/plugins-claude/inbox/scripts/inbox"
run sync --check
check "--check fails on claude-target drift" nonzero "$RC"

# --- drift on the opencode target is detected ---------------------------------
run sync # resync first
echo "# tampered" >>"$S/plugins-opencode/inbox/scripts/inbox"
run sync --check
check "--check fails on opencode-target drift" nonzero "$RC"
if [[ -z "$FILTER" ]] || echo "opencode drift names path" | grep -qi "$FILTER"; then
	if echo "$ERR" | grep -q "plugins-opencode/inbox/scripts/inbox"; then
		pass "--check names the drifted opencode path"
	else
		fail "--check names the drifted opencode path" "stderr: $ERR"
	fi
fi

# --- missing vendored file is drift --------------------------------------------
run sync
rm "$S/plugins-opencode/session/skills/session-start/scripts/git-wait"
run sync --check
check "--check fails on missing vendored file" nonzero "$RC"

# --- rendered markdown drift is detected too -------------------------------------
run sync
echo "# tampered" >>"$S/plugins-opencode/session/skills/session-issue/reference/spine.md"
run sync --check
check "--check fails on rendered markdown drift" nonzero "$RC"

# --- missing canonical source is a hard error -----------------------------------
run sync
rm "$S/utils/branch"
run sync --check
check "missing canonical source exits non-zero" nonzero "$RC"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
