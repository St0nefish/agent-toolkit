#!/usr/bin/env bash
# test-skills-catalog.sh — the HTTP skills catalog (utils/skills-catalog.py).
#
# Two jobs: (1) sandbox tests of the generator itself — clean generate,
# --check cleanliness, drift detection in every direction (tampered file,
# missing file, stray file, changed source), version bumping; (2) integrity
# checks on the COMMITTED skills-catalog/ — index.json shape, byte-identity
# with the skill sources, and the real --check gate that CI enforces.
#
# Usage: bash tests/opencode/test-skills-catalog.sh [filter]

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
  if [[ -n "$FILTER" ]] && ! echo "$*" | grep -qi "$FILTER"; then
    RC=0
    return
  fi
  OUT=$("$@" 2>"$TMP/err") && RC=0 || RC=$?
  ERR=$(cat "$TMP/err")
}

# ---------------------------------------------------------------------------
# Sandbox: copy the generator + skill sources, never touch the real trees
# ---------------------------------------------------------------------------
S="$TMP/repo"
mkdir -p "$S/utils" "$S/plugins-opencode/git-tools" "$S/plugins-opencode/session"
cp "$REPO/utils/skills-catalog.py" "$S/utils/"
cp -r "$REPO/plugins-opencode/git-tools/skills" "$S/plugins-opencode/git-tools/skills"
cp -r "$REPO/plugins-opencode/session/skills" "$S/plugins-opencode/session/skills"
CAT="$S/utils/skills-catalog.py"

run python3 "$CAT"
check "generate succeeds" 0 "$RC"
run test -f "$S/skills-catalog/index.json"
check "index.json generated" 0 "$RC"

# index shape: 7 skills, every entry has SKILL.md, safe relative paths
run python3 - "$S/skills-catalog/index.json" <<'EOF'
import json, sys
idx = json.load(open(sys.argv[1]))
names = [s["name"] for s in idx["skills"]]
assert names == sorted(names), "skills not sorted"
assert len(names) == 7, f"expected 7 skills, got {names}"
for s in idx["skills"]:
    assert s["version"], f"{s['name']}: empty version"
    assert "SKILL.md" in s["files"], f"{s['name']}: no SKILL.md"
    for f in s["files"]:
        assert not f.startswith("/") and ".." not in f.split("/"), f"{s['name']}: unsafe path {f}"
EOF
check "index.json shape (7 skills, sorted, SKILL.md, safe paths)" 0 "$RC"

run python3 "$CAT" --check
check "--check clean after generate" 0 "$RC"

# --- drift detection, every direction --------------------------------------
printf '\n# tampered\n' >>"$S/skills-catalog/git-wait/SKILL.md"
run python3 "$CAT" --check
check "--check fails on tampered catalog file" nonzero "$RC"
if echo "$ERR" | grep -q "differs"; then pass "--check names the differing file"; else fail "--check names the differing file" "stderr: $ERR"; fi

run python3 "$CAT"
check "regenerate repairs tampered file" 0 "$RC"
run python3 "$CAT" --check
check "--check clean after repair" 0 "$RC"

rm "$S/skills-catalog/session-summarize/scripts/sitrep"
run python3 "$CAT" --check
check "--check fails on missing catalog file" nonzero "$RC"
if echo "$ERR" | grep -q "missing"; then pass "--check names the missing file"; else fail "--check names the missing file" "stderr: $ERR"; fi

echo stray >"$S/skills-catalog/git-wait/STRAY.md"
run python3 "$CAT" --check
check "--check fails on stray catalog file" nonzero "$RC"
if echo "$ERR" | grep -q "not generated"; then pass "--check names the stray file"; else fail "--check names the stray file" "stderr: $ERR"; fi
rm "$S/skills-catalog/git-wait/STRAY.md"

# source drift: editing a skill must invalidate the committed catalog
v_before=$(python3 -c "import json;print([s['version'] for s in json.load(open('$S/skills-catalog/index.json'))['skills'] if s['name']=='git-wait'][0])")
printf '\nextra line\n' >>"$S/plugins-opencode/git-tools/skills/git-wait/SKILL.md"
run python3 "$CAT" --check
check "--check fails when a skill source changed" nonzero "$RC"
run python3 "$CAT"
v_after=$(python3 -c "import json;print([s['version'] for s in json.load(open('$S/skills-catalog/index.json'))['skills'] if s['name']=='git-wait'][0])")
if [[ "$v_before" != "$v_after" ]]; then pass "version hash bumps on content change"; else fail "version hash bumps on content change" "$v_before == $v_after"; fi

# new skill appears automatically
mkdir -p "$S/plugins-opencode/session/skills/session-new"
echo '---
name: new
---
body' >"$S/plugins-opencode/session/skills/session-new/SKILL.md"
run python3 "$CAT"
run python3 -c "import json;import sys;names=[s['name'] for s in json.load(open('$S/skills-catalog/index.json'))['skills']];sys.exit(0 if 'session-new' in names else 1)"
check "new skill picked up on regenerate" 0 "$RC"

# hidden files / node_modules excluded
mkdir -p "$S/plugins-opencode/session/skills/session-new/.hidden" "$S/plugins-opencode/session/skills/session-new/node_modules"
echo x >"$S/plugins-opencode/session/skills/session-new/.hidden/x"
echo x >"$S/plugins-opencode/session/skills/session-new/node_modules/y"
run python3 "$CAT"
run python3 -c "import json;import sys;s=[x for x in json.load(open('$S/skills-catalog/index.json'))['skills'] if x['name']=='session-new'][0];sys.exit(0 if all('/.' not in '/'+f and 'node_modules' not in f for f in s['files']) else 1)"
check "hidden dirs and node_modules excluded" 0 "$RC"

# ---------------------------------------------------------------------------
# The committed catalog: byte-identity with sources + the real CI gate
# ---------------------------------------------------------------------------
run python3 "$REPO/utils/skills-catalog.py" --check
check "committed skills-catalog/ is up to date (CI gate)" 0 "$RC"

run python3 - "$REPO" <<'EOF'
import json, sys
from pathlib import Path
repo = Path(sys.argv[1])
idx = json.load(open(repo / "skills-catalog/index.json"))
sources = list((repo / "plugins-opencode/git-tools/skills").iterdir()) + \
          list((repo / "plugins-opencode/session/skills").iterdir())
src = {d.name: d for d in sources if d.is_dir()}
for s in idx["skills"]:
    for f in s["files"]:
        a = (repo / "skills-catalog" / s["name"] / f).read_bytes()
        b = (src[s["name"]] / f).read_bytes()
        assert a == b, f"{s['name']}/{f}: catalog copy differs from source"
EOF
check "every catalog file is byte-identical to its skill source" 0 "$RC"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
