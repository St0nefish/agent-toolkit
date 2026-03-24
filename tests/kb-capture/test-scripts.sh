#!/usr/bin/env bash
# test-scripts.sh — Test harness for kb-capture utility scripts.
# Tests detect-schema.sh and validate-frontmatter.sh (from utils/).
#
# Usage: bash tests/kb-capture/test-scripts.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UTILS="$SCRIPT_DIR/../../utils"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# Create a temporary directory for test fixtures
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

run_test() {
  local expected_exit="$1" label="$2"
  shift 2
  local cmd=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local actual_exit=0
  "${cmd[@]}" >/dev/null 2>&1 || actual_exit=$?

  if [[ $actual_exit -eq $expected_exit ]]; then
    printf "  \033[32m✓\033[0m exit=%d  %s\n" "$expected_exit" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m exit=%d  %s  (got: %d)\n" "$expected_exit" "$label" "$actual_exit"
    ((FAIL++)) || true
  fi
}

run_test_output() {
  local expected_pattern="$1" label="$2"
  shift 2
  local cmd=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output
  output=$("${cmd[@]}" 2>/dev/null) || true

  if echo "$output" | grep -qE "$expected_pattern"; then
    printf "  \033[32m✓\033[0m match  %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m match  %s  (output: %.80s)\n" "$label" "$output"
    ((FAIL++)) || true
  fi
}

# ===== detect-schema.sh =====
echo "── detect-schema.sh ──"

# No schema file present → empty fields (run from clean temp dir)
run_test_output '"schema_file":[[:space:]]*""' \
  "no schema → empty output" \
  bash -c "cd '$TMPDIR' && bash '$UTILS/detect-schema.sh'"

# Valid JSON output (even with no schema)
output=$(cd "$TMPDIR" && bash "$UTILS/detect-schema.sh" 2>/dev/null) || true
if echo "$output" | jq -e . >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m valid  no schema → valid JSON\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m valid  no schema → valid JSON  (output: %.80s)\n" "$output"
  ((FAIL++)) || true
fi

# Schema present → correct JSON with fields
mkdir -p "$TMPDIR/schema-test"
cat >"$TMPDIR/schema-test/schema.md" <<'SCHEMA'
# Knowledge Base Schema

## Available type

- guide
- reference
- research

## Available domain

- dev
- sysadmin

## Available status

- active
- draft
SCHEMA

output=$(cd "$TMPDIR/schema-test" && bash "$UTILS/detect-schema.sh" 2>/dev/null) || true
if echo "$output" | jq -e '.schema_file != ""' >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m match  schema present → schema_file populated\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m match  schema present → schema_file populated  (output: %.80s)\n" "$output"
  ((FAIL++)) || true
fi

if echo "$output" | jq -e '.fields.type | length > 0' >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m match  schema present → type field has values\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m match  schema present → type field has values  (output: %.80s)\n" "$output"
  ((FAIL++)) || true
fi

if echo "$output" | jq -e '.fields.type | index("guide")' >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m match  schema present → type contains 'guide'\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m match  schema present → type contains 'guide'  (output: %.80s)\n" "$output"
  ((FAIL++)) || true
fi

# Schema in parent directory (walk-up) — needs a git repo so walk-up activates
mkdir -p "$TMPDIR/schema-test/subdir/deep"
git -C "$TMPDIR/schema-test" init -q 2>/dev/null || true
output=$(cd "$TMPDIR/schema-test/subdir/deep" && bash "$UTILS/detect-schema.sh" 2>/dev/null) || true
if echo "$output" | jq -e '.schema_file != ""' >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m match  schema in parent → found via walk-up\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m match  schema in parent → found via walk-up  (output: %.80s)\n" "$output"
  ((FAIL++)) || true
fi

# ===== validate-frontmatter.sh =====
echo "── validate-frontmatter.sh ──"

# Valid file → exit 0
cat >"$TMPDIR/valid.md" <<'EOF'
---
title: Test Document
date: 2026-03-19
type: guide
---

# Test

Content here.
EOF

run_test 0 "valid file → exit 0" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/valid.md"

# Missing title → exit 1
cat >"$TMPDIR/no-title.md" <<'EOF'
---
date: 2026-03-19
---

Content.
EOF

run_test 1 "missing title → exit 1" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/no-title.md"

# Bad date format → exit 1
cat >"$TMPDIR/bad-date.md" <<'EOF'
---
title: Test
date: March 19, 2026
---

Content.
EOF

run_test 1 "bad date format → exit 1" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/bad-date.md"

# Missing date → exit 1
cat >"$TMPDIR/no-date.md" <<'EOF'
---
title: Test
---

Content.
EOF

run_test 1 "missing date → exit 1" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/no-date.md"

# No frontmatter at all → exit 1
cat >"$TMPDIR/no-fm.md" <<'EOF'
# Just a heading

No frontmatter here.
EOF

run_test 1 "no frontmatter → exit 1" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/no-fm.md"

# Invalid constrained value → exit 1 (when schema is available)
cat >"$TMPDIR/bad-type.md" <<'EOF'
---
title: Test
date: 2026-03-19
type: invalid-type
---

Content.
EOF

# Run from schema-test dir so detect-schema.sh finds the schema
run_test 1 "invalid constrained value → exit 1" \
  bash -c "cd '$TMPDIR/schema-test' && bash '$UTILS/validate-frontmatter.sh' '$TMPDIR/bad-type.md'"

# No args → exit 2
run_test 2 "no args → exit 2" \
  bash "$UTILS/validate-frontmatter.sh"

# Nonexistent file → exit 2
run_test 2 "nonexistent file → exit 2" \
  bash "$UTILS/validate-frontmatter.sh" "$TMPDIR/nonexistent.md"

# ===== Summary =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
if [[ $SKIP -gt 0 ]]; then
  printf "  \033[33m%d skipped\033[0m" "$SKIP"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
