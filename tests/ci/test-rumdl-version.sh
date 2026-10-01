#!/usr/bin/env bash
# test-rumdl-version.sh — Tests for .github/scripts/check-rumdl-version.sh, which
# warns when the local rumdl differs from the release CI pins.
#
# Usage: bash tests/ci/test-rumdl-version.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/../.."
CHECK="$REPO/.github/scripts/check-rumdl-version.sh"
REAL_WORKFLOW="$REPO/.github/workflows/ci.yml"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

filtered() {
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

check() {
  local label="$1" expected="$2" actual="$3"
  if filtered "$label"; then
    ((SKIP++)) || true
    return 0
  fi
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: %q, got: %q)\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

# A workflow that pins the given rumdl version, in the same shape as ci.yml.
write_workflow() {
  local version="$1" file="$2"
  cat >"$file" <<EOF
steps:
  - name: Install rumdl
    run: |
      curl -sSL https://github.com/rvben/rumdl/releases/download/v${version}/rumdl-v${version}-x86_64-unknown-linux-gnu.tar.gz | tar xz
EOF
}

# A fake `rumdl` that reports the given version (stands alone: it never
# delegates to a real binary, so it cannot recurse through PATH).
write_rumdl() {
  local version="$1" dir="$2"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "rumdl %s"\n' "$version" >"$dir/rumdl"
  chmod +x "$dir/rumdl"
}

# run_check_script <workflow> <path-prefix> → sets OUT (stdout+stderr) and RC
run_script() {
  local workflow="$1" path_prefix="$2"
  RC=0
  OUT=$(PATH="$path_prefix:$PATH" bash "$CHECK" "$workflow" 2>&1) || RC=$?
}

echo "── version match ──"
write_workflow "1.2.3" "$TMP/wf-match.yml"
write_rumdl "1.2.3" "$TMP/bin-match"
run_script "$TMP/wf-match.yml" "$TMP/bin-match"
check "same version → reports match" "rumdl 1.2.3 matches CI" "$OUT"
check "same version → exit 0" "0" "$RC"

echo "── version mismatch ──"
write_workflow "0.1.53" "$TMP/wf-old.yml"
write_rumdl "0.2.69" "$TMP/bin-new"
run_script "$TMP/wf-old.yml" "$TMP/bin-new"
check "mismatch → warns" "true" "$([[ "$OUT" == WARNING:* ]] && echo true || echo false)"
check "mismatch → names both versions" "true" \
  "$([[ "$OUT" == *"0.2.69"* && "$OUT" == *"v0.1.53"* ]] && echo true || echo false)"
check "mismatch → still exit 0 (warning only)" "0" "$RC"

echo "── rumdl not installed ──"
# A PATH holding only the tools the script itself needs, so rumdl is absent
# even on a machine that has it installed system-wide.
BARE="$TMP/bare"
mkdir -p "$BARE"
for tool in grep sed head dirname; do
  ln -s "$(command -v "$tool")" "$BARE/$tool"
done
RC=0
OUT=$(PATH="$BARE" "$(command -v bash)" "$CHECK" "$TMP/wf-match.yml" 2>&1) || RC=$?
check "no rumdl → warns, names pinned version" "true" \
  "$([[ "$OUT" == WARNING:*"v1.2.3"* ]] && echo true || echo false)"
check "no rumdl → exit 0" "0" "$RC"

echo "── bad input ──"
printf 'steps: []\n' >"$TMP/wf-none.yml"
run_script "$TMP/wf-none.yml" "$TMP/bin-match"
check "no pinned version in workflow → exit 1" "1" "$RC"
run_script "$TMP/does-not-exist.yml" "$TMP/bin-match"
check "missing workflow file → exit 1" "1" "$RC"

echo "── the real workflow ──"
pinned=$(grep -oE 'rvben/rumdl/releases/download/v[0-9]+\.[0-9]+\.[0-9]+' "$REAL_WORKFLOW" | head -1 | sed -E 's|.*/v||')
write_rumdl "$pinned" "$TMP/bin-real"
run_script "$REAL_WORKFLOW" "$TMP/bin-real"
check "ci.yml pins a parseable version that the check accepts" "0" "$RC"
check "download URL version and filename version agree" "1" \
  "$(grep -oE 'rumdl-v[0-9]+\.[0-9]+\.[0-9]+-x86_64' "$REAL_WORKFLOW" | sed -E 's/^rumdl-v//; s/-x86_64$//' | sort -u | grep -cFx "$pinned")"

echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
