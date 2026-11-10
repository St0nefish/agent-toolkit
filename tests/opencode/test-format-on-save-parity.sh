#!/usr/bin/env bash
# test-format-on-save-parity.sh — the OpenCode formatter config must mirror
# the Claude hook's dispatch table (plugins-claude/format-on-save/
# scripts/format-on-save.sh). Same extension set, same tool + flags, so a
# file formatted by either harness is byte-identical. If someone edits one
# side and forgets the other, this fails.
#
# Usage: bash tests/opencode/test-format-on-save-parity.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."
HOOK="$REPO/plugins-claude/format-on-save/scripts/format-on-save.sh"
SNIPPET="$REPO/plugins-opencode/format-on-save/opencode.jsonc"

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

# --- extract the hook's dispatch: one "ext<TAB>fmt_fn" line per extension ---
# Drop the `case`/`esac` lines, flatten, split arms on ;;, split alternates on |.
sed -n '/^case "\$ext" in/,/^esac/p' "$HOOK" | sed '1d;$d' | tr '\n' ' ' |
	sed -E 's/ *\| */ /g; s/;;/\n/g' |
	awk -F')' '/fmt_/ {
		fn = $2; sub(/^ +/, "", fn); sub(/ +.*$/, "", fn)
		n = split($1, a, / +/)
		for (i = 1; i <= n; i++) if (a[i] ~ /^[a-z]+$/) print a[i] "\t" fn
	}' >"$TMP/extfn"

if [[ ! -s "$TMP/extfn" ]]; then
	fail "parsed hook dispatch table" "empty parse — did the case block shape change?"
	echo ""
	echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
	exit 1
fi
pass "parsed hook dispatch table ($(wc -l <"$TMP/extfn") extensions)"

# fmt_<fn> → argv: the `if ! <cmd> "$file_path" 2>&1` line, with $FILE for
# "$file_path". fmt_cargo_fmt is special-cased: per-file OpenCode formatters
# run rustfmt directly (documented divergence).
argv_for() {
	local fn="$1"
	if [[ "$fn" == "fmt_cargo_fmt" ]]; then
		echo "rustfmt \$FILE"
		return
	fi
	awk -v fn="$fn" '$0 == fn"() {" {infn=1} infn && /if ! / && !/command -v/ {
		sub(/^ +if ! /, "")
		sub(/ "[$]file_path" 2>&1; then/, " $FILE")
		print
		exit
	} infn && /^}/ {infn=0}' "$HOOK"
}

: >"$TMP/script_table"
while IFS=$'\t' read -r ext fn; do
	argv=$(argv_for "$fn")
	if [[ -z "$argv" ]]; then
		fail "extract command for $fn" "no 'if ! …' invocation found — did the function shape change?"
		continue
	fi
	printf '%s\t%s\n' "$ext" "$argv" >>"$TMP/script_table"
done <"$TMP/extfn"

# --- extract the snippet's table: one "ext<TAB>argv" line per extension ----
node -e '
	const s = require("fs").readFileSync(process.argv[1], "utf8")
		.replace(/^\s*\/\/.*$/gm, "")
		.replace(/,(\s*[}\]])/g, "$1");
	const fmt = JSON.parse(s).formatter
	for (const [name, def] of Object.entries(fmt))
		for (const ext of def.extensions)
			console.log(ext.slice(1) + "\t" + def.command.join(" "))
' "$SNIPPET" >"$TMP/snippet_table"

# --- compare -----------------------------------------------------------------
# Every extension the hook formats must be formatted identically by the snippet.
while IFS=$'\t' read -r ext argv; do
	if [[ -n "$FILTER" ]] && ! echo "$ext" | grep -qi "$FILTER"; then continue; fi
	actual=$(awk -F'\t' -v e="$ext" '$1 == e {print $2}' "$TMP/snippet_table")
	if [[ -z "$actual" ]]; then
		fail "$ext covered by snippet" "missing from formatter config"
	elif [[ "$actual" == "$argv" ]]; then
		pass "$ext → $argv"
	else
		fail "$ext command parity" "hook: '$argv' vs snippet: '$actual'"
	fi
done <"$TMP/script_table"

# No extra extensions in the snippet the hook doesn't format (prettier's
# built-in grab-bag must not sneak .md/.toml back in).
while IFS=$'\t' read -r ext argv; do
	if ! grep -q "^$ext"$'\t' "$TMP/script_table"; then
		fail "snippet has no extra ext: $ext" "not formatted by the Claude hook"
	else
		pass "snippet has no extra ext: $ext"
	fi
done <"$TMP/snippet_table"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
