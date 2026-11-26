#!/usr/bin/env bash
# test-copilot-skills-port.sh — the generated Copilot skill copies stay faithful.
# For the plugins whose plugins-copilot/<p>/skills used to be a symlink, the
# copies must match utils/port-copilot-skills.py (--check clean), carry no
# `when_to_use:` (Copilot ignores it), hold the folded text in `description`,
# contain no symlinks, and the shared fold must handle quoting and blank lines.
#
# Usage: bash tests/copilot-port/test-copilot-skills-port.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."
PORTER="$REPO/utils/port-copilot-skills.py"
HELPER="$REPO/utils/skill-frontmatter.py"
PLUGINS="agentic-ide convert-doc elevated-edit freecad git-tools image stl-game-config"

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
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "assertion failed: $*"; fi
}

t2 "port-copilot-skills --check is clean" python3 "$PORTER" --check

# Per-plugin: every Claude skill with when_to_use has it folded into description.
cat >"$TMP/folded.py" <<'PYEOF'
import sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
repo, plugin = Path(sys.argv[1]), sys.argv[2]
spec = spec_from_file_location("fm", repo / "utils" / "skill-frontmatter.py")
fm = module_from_spec(spec); spec.loader.exec_module(fm)
n = 0
base = repo / "plugins-claude" / plugin / "skills"
for src in sorted(base.rglob("SKILL.md")):
    rel = src.relative_to(base)
    dst = repo / "plugins-copilot" / plugin / "skills" / rel
    w = fm.frontmatter_value(src.read_text(), "when_to_use")
    if w is None:
        continue
    desc = fm.frontmatter_value(dst.read_text(), "description")
    assert w in desc, f"{rel}: when_to_use text missing from description"
    assert len(desc) <= 1024, f"{rel}: description too long ({len(desc)})"
    n += 1
assert n > 0, "no skill with when_to_use found"
PYEOF

for p in $PLUGINS; do
  dst="$REPO/plugins-copilot/$p/skills"
  t2 "$p: skills is a real directory" sh -c "[ -d '$dst' ] && [ ! -L '$dst' ]"
  t2 "$p: no symlinks under skills" sh -c "[ -z \"\$(find '$dst' -type l)\" ]"
  t2 "$p: no when_to_use in generated SKILL.md" sh -c "! grep -rq '^when_to_use:' '$dst' --include=SKILL.md"
  t2 "$p: description contains folded when_to_use" python3 "$TMP/folded.py" "$REPO" "$p"
done

# --- the shared fold handles the quoting and block edge cases -----------------
cat >"$TMP/fold.py" <<'PYEOF'
import sys
from importlib.util import module_from_spec, spec_from_file_location
spec = spec_from_file_location("fm", sys.argv[1])
fm = module_from_spec(spec); spec.loader.exec_module(fm)

def doc(t):
    return "---\n" + t + "---\nbody\n"

# double-quoted: \" and \\ decode
out = fm.fold_when_to_use(doc('name: x\ndescription: "Say \\"hi\\" in C:\\\\dir."\nwhen_to_use: "Use it."\nallowed-tools: Bash\n'))
assert fm.frontmatter_value(out, "description") == 'Say "hi" in C:\\dir. Use it.', out
assert "when_to_use" not in out and "allowed-tools: Bash" in out, out

# single-quoted: '' decodes
out = fm.fold_when_to_use(doc("name: x\ndescription: 'It''s here.'\nwhen_to_use: 'Use it.'\n"))
assert fm.frontmatter_value(out, "description") == "It's here. Use it.", out
PYEOF
cat >"$TMP/fold-block.py" <<'PYEOF'
import sys
from importlib.util import module_from_spec, spec_from_file_location
spec = spec_from_file_location("fm", sys.argv[1])
fm = module_from_spec(spec); spec.loader.exec_module(fm)

def doc(t):
    return "---\n" + t + "---\nbody\n"

# blank line inside a >- block must not truncate; later keys stay intact
out = fm.fold_when_to_use(doc("name: x\ndescription: >-\n  First part\n\n  second part.\nwhen_to_use: >-\n  Use when A\n\n  or B.\nallowed-tools: Bash\n"))
v = fm.frontmatter_value(out, "description")
assert v == "First part second part. Use when A or B.", repr(v)
assert "allowed-tools: Bash" in out and out.endswith("---\nbody\n"), out

# a trailing blank line before the next key is not swallowed into the block
out = fm.fold_when_to_use(doc("name: x\ndescription: >-\n  One\n\nwhen_to_use: Two\n"))
assert fm.frontmatter_value(out, "description") == "One Two", out
PYEOF
t2 "fold: escaped quotes and '' decode" python3 "$TMP/fold.py" "$HELPER"
t2 "fold: blank line inside a block does not truncate" python3 "$TMP/fold-block.py" "$HELPER"

# --- unsupported frontmatter shapes raise instead of producing wrong text ------
cat >"$TMP/fold-bad.py" <<'PYEOF'
import sys
from importlib.util import module_from_spec, spec_from_file_location
spec = spec_from_file_location("fm", sys.argv[1])
fm = module_from_spec(spec); spec.loader.exec_module(fm)

def doc(t):
    return "---\n" + t + "---\nbody\n"

def raises(label, text, key):
    try:
        fm.fold_when_to_use(text)
    except ValueError as e:
        assert key in str(e), f"{label}: error does not name {key}: {e}"
        return
    raise AssertionError(f"{label}: did not raise")

raises("bad escape", doc('name: x\ndescription: "a\\nb"\nwhen_to_use: Use.\n'), "description")
raises("unclosed", doc('name: x\ndescription: "abc\nwhen_to_use: Use.\n'), "description")
raises("trailing comment", doc('name: x\ndescription: "abc" # c\nwhen_to_use: Use.\n'), "description")
raises("trailing in when_to_use", doc("name: x\ndescription: Do.\nwhen_to_use: 'abc' # c\n"), "when_to_use")
raises("plain continuation", doc("name: x\ndescription: Do it\n  and more\nwhen_to_use: Use.\n"), "description")
raises("crlf", "---\r\nname: x\r\ndescription: Do.\r\nwhen_to_use: Use.\r\n---\r\nbody\r\n", "frontmatter")

# supported shapes still work, including | flattened to spaces
out = fm.fold_when_to_use(doc("name: x\ndescription: |\n  one\n  two\nwhen_to_use: Use.\n"))
assert fm.frontmatter_value(out, "description") == "one two Use.", out
PYEOF
t2 "fold: unsupported shapes raise, supported ones work" python3 "$TMP/fold-bad.py" "$HELPER"

# --- generator behaviour, run against a temp copy of the tree -------------------
# mkroot DIR: DIR/utils plus plugins-claude/<p>/skills and plugins-copilot/<p>/skills.
mkroot() {
  local r="$1" p
  mkdir -p "$r/utils"
  cp "$HELPER" "$PORTER" "$r/utils/"
  for p in $PLUGINS; do
    mkdir -p "$r/plugins-claude/$p" "$r/plugins-copilot/$p"
    cp -a "$REPO/plugins-claude/$p/skills" "$r/plugins-claude/$p/skills"
    cp -a "$REPO/plugins-copilot/$p/skills" "$r/plugins-copilot/$p/skills"
  done
}
gen() { python3 "$1/utils/port-copilot-skills.py" "${@:2}"; }
# rc_is N CMD...: command exits with status N.
rc_is() {
  local want="$1" rc=0
  shift
  "$@" >/dev/null 2>&1 || rc=$?
  [[ $rc -eq $want ]]
}
# Pick a destination SKILL.md to tamper with.
victim() { find "$1/plugins-copilot/image/skills" -name SKILL.md | sort | head -1; }

R="$TMP/root-clean"
mkroot "$R"
t2 "temp root: --check is clean" rc_is 0 gen "$R" --check

R="$TMP/root-mod"
mkroot "$R"
echo "tampered" >>"$(victim "$R")"
t2 "--check exits 1 after a generated file is modified" rc_is 1 gen "$R" --check

R="$TMP/root-add"
mkroot "$R"
echo x >"$R/plugins-copilot/image/skills/extra.txt"
t2 "--check exits 1 after an extra file is added" rc_is 1 gen "$R" --check

R="$TMP/root-del"
mkroot "$R"
rm -f "$(victim "$R")"
t2 "--check exits 1 after a generated file is deleted" rc_is 1 gen "$R" --check

R="$TMP/root-stale"
mkroot "$R"
echo x >"$R/plugins-copilot/image/skills/extra.txt"
t2 "write mode deletes a stale extra file" sh -c \
  "python3 '$R/utils/port-copilot-skills.py' && [ ! -e '$R/plugins-copilot/image/skills/extra.txt' ] && python3 '$R/utils/port-copilot-skills.py' --check"

# A description over 1024 chars fails the run and leaves the destination alone.
R="$TMP/root-long"
mkroot "$R"
long_src=$(find "$R/plugins-claude/image/skills" -name SKILL.md | sort | head -1)
{
  printf -- '---\nname: long\ndescription: %s\n---\nbody\n' "$(head -c 1100 /dev/zero | tr '\0' a)"
} >"$long_src"
echo "tampered" >>"$(victim "$R")"
snap_before=$(cd "$R/plugins-copilot" && find . -type f -exec cksum {} + | sort)
t2 "over-long description exits non-zero with the limit error" sh -c "! python3 '$R/utils/port-copilot-skills.py' 2>'$TMP/long.err' && grep -q 'limit 1024' '$TMP/long.err'"
snap_after=$(cd "$R/plugins-copilot" && find . -type f -exec cksum {} + | sort)
t2 "over-long description leaves destination unchanged" test "$snap_before" = "$snap_after"

# A symlink under a destination skills dir makes both modes refuse.
R="$TMP/root-link"
mkroot "$R"
ln -s /etc/hostname "$R/plugins-copilot/git-tools/skills/link"
t2 "symlink under destination refused (write)" sh -c "! python3 '$R/utils/port-copilot-skills.py' 2>'$TMP/link.err' && grep -q 'is a symlink' '$TMP/link.err'"
t2 "symlink under destination refused (--check)" sh -c "! python3 '$R/utils/port-copilot-skills.py' --check 2>'$TMP/link.err' && grep -q 'is a symlink' '$TMP/link.err'"
t2 "symlink under destination left in place" test -L "$R/plugins-copilot/git-tools/skills/link"

# A bad frontmatter shape in a source exits 1 and names the file.
R="$TMP/root-badfm"
mkroot "$R"
bad_src=$(find "$R/plugins-claude/image/skills" -name SKILL.md | sort | head -1)
printf -- '---\nname: bad\ndescription: "a\\nb"\nwhen_to_use: Use.\n---\nbody\n' >"$bad_src"
t2 "bad frontmatter exits 1" rc_is 1 gen "$R"
t2 "bad frontmatter error names the source file" sh -c \
  "python3 '$R/utils/port-copilot-skills.py' 2>&1 | grep -q 'SKILL.md: description:'"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
