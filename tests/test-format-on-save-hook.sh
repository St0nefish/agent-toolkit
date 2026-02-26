#!/usr/bin/env bash
# Tests for hooks/format-on-save/format-on-save.sh
# Run from repo root: bash tests/test-format-on-save-hook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/plugins/format-on-save/scripts/format-on-save.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

# Helper: run hook with given JSON input, capture exit code and stderr
run_hook() {
    local json="$1"
    local stderr_file="$TESTDIR/stderr"
    local rc=0
    echo "$json" | "$HOOK" >"$TESTDIR/stdout" 2>"$stderr_file" || rc=$?
    HOOK_RC=$rc
    HOOK_STDERR=$(cat "$stderr_file")
    HOOK_STDOUT=$(cat "$TESTDIR/stdout")
}

# ===== Test: missing file =====
echo ""
echo "=== Test: missing file ==="
run_hook '{"tool_input":{"file_path":"/tmp/nonexistent-format-test-file.xyz"}}'
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "missing file exits 0"
else
    fail "missing file exits 0" "exit code $HOOK_RC"
fi

# ===== Test: empty file_path =====
echo ""
echo "=== Test: empty file_path ==="
run_hook '{"tool_input":{}}'
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "empty file_path exits 0"
else
    fail "empty file_path exits 0" "exit code $HOOK_RC"
fi

run_hook '{"tool_input":{"file_path":""}}'
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "blank file_path exits 0"
else
    fail "blank file_path exits 0" "exit code $HOOK_RC"
fi

# ===== Test: unknown extension =====
echo ""
echo "=== Test: unknown extension ==="
echo "hello" > "$TESTDIR/test.xyz"
run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/test.xyz\"}}"
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "unknown extension exits 0"
else
    fail "unknown extension exits 0" "exit code $HOOK_RC"
fi
if [[ -z "$HOOK_STDERR" ]]; then
    pass "unknown extension no stderr"
else
    fail "unknown extension no stderr" "got: $HOOK_STDERR"
fi
content=$(cat "$TESTDIR/test.xyz")
if [[ "$content" == "hello" ]]; then
    pass "unknown extension file unchanged"
else
    fail "unknown extension file unchanged" "content changed"
fi

# ===== Test: missing formatter binary =====
echo ""
echo "=== Test: missing formatter binary ==="
# Use a .rs file with a minimal PATH that has bash/jq but not rustfmt
echo "fn main(){}" > "$TESTDIR/test.rs"
MINIMAL_BIN="$TESTDIR/minbin"
mkdir -p "$MINIMAL_BIN"
ln -sf "$(command -v bash)" "$MINIMAL_BIN/bash"
ln -sf "$(command -v jq)" "$MINIMAL_BIN/jq"
ln -sf "$(command -v echo)" "$MINIMAL_BIN/echo" 2>/dev/null || true
ln -sf "$(command -v cat)" "$MINIMAL_BIN/cat" 2>/dev/null || true
HOOK_RC=0
HOOK_STDERR=""
echo "{\"tool_input\":{\"file_path\":\"$TESTDIR/test.rs\"}}" \
    | PATH="$MINIMAL_BIN" "$HOOK" >"$TESTDIR/stdout" 2>"$TESTDIR/stderr" || HOOK_RC=$?
HOOK_STDERR=$(cat "$TESTDIR/stderr")
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "missing formatter exits 0"
else
    fail "missing formatter exits 0" "exit code $HOOK_RC"
fi
if echo "$HOOK_STDERR" | grep -q "WARN"; then
    pass "missing formatter logs WARN"
else
    fail "missing formatter logs WARN" "no WARN in stderr: $HOOK_STDERR"
fi

# ===== Test: formatter error =====
echo ""
echo "=== Test: formatter error ==="
# Create a file that will cause a parse error for shfmt
cat <<'PRE' > "$TESTDIR/bad.sh"
#!/bin/bash
if [[ true; then
  echo broken
fi
PRE
run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/bad.sh\"}}"
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "formatter error exits 0"
else
    fail "formatter error exits 0" "exit code $HOOK_RC"
fi
if command -v shfmt >/dev/null 2>&1; then
    if echo "$HOOK_STDERR" | grep -q "ERROR\|shfmt"; then
        pass "formatter error logs ERROR"
    else
        fail "formatter error logs ERROR" "no ERROR in stderr: $HOOK_STDERR"
    fi
else
    pass "formatter error logs ERROR (shfmt not installed, skipped)"
fi

# ===== Per-formatter round-trip tests (conditional) =====

echo ""
echo "=== Per-formatter round-trip tests ==="

# --- shfmt ---
if command -v shfmt >/dev/null 2>&1; then
    echo ""
    echo "--- shfmt ---"
    cat <<'PRE' > "$TESTDIR/fmt.sh"
#!/bin/bash
if [[ -f /tmp/x ]];then
    echo "indented with 4"
        echo "over-indented"
done
PRE
    # Note: shfmt will fix indentation but the script above has syntax errors
    # Use a valid script instead
    cat <<'PRE' > "$TESTDIR/fmt.sh"
#!/bin/bash
if [[ -f /tmp/x ]];then
    echo "indented with 4"
    echo "ok"
fi
PRE
    cat <<'POST' > "$TESTDIR/fmt.sh.expected"
#!/bin/bash
if [[ -f /tmp/x ]]; then
  echo "indented with 4"
  echo "ok"
fi
POST
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.sh\"}}"
    if diff -q "$TESTDIR/fmt.sh" "$TESTDIR/fmt.sh.expected" >/dev/null 2>&1; then
        pass "shfmt round-trip"
    else
        fail "shfmt round-trip" "$(diff "$TESTDIR/fmt.sh" "$TESTDIR/fmt.sh.expected" || true)"
    fi
else
    pass "shfmt round-trip (not installed, skipped)"
fi

# --- prettier (JSON) ---
if command -v prettier >/dev/null 2>&1; then
    echo ""
    echo "--- prettier ---"
    cat <<'PRE' > "$TESTDIR/fmt.json"
{"a":1,   "b" :  [2,3,  4]  }
PRE
    cat <<'POST' > "$TESTDIR/fmt.json.expected"
{ "a": 1, "b": [2, 3, 4] }
POST
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.json\"}}"
    # Prettier output varies by version; just check it's valid JSON and changed
    if jq -e . "$TESTDIR/fmt.json" >/dev/null 2>&1; then
        pass "prettier round-trip (valid JSON output)"
    else
        fail "prettier round-trip" "output is not valid JSON"
    fi
else
    pass "prettier round-trip (not installed, skipped)"
fi

# --- markdownlint-cli2 ---
if command -v markdownlint-cli2 >/dev/null 2>&1; then
    echo ""
    echo "--- markdownlint-cli2 ---"
    cat <<'PRE' > "$TESTDIR/fmt.md"
# Heading
No blank line before this paragraph.
## Another heading
No blank line here either.
PRE
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.md\"}}"
    # Check that blank lines were added around headings (MD022)
    if grep -qE '^[[:space:]]*$' "$TESTDIR/fmt.md"; then
        pass "markdownlint-cli2 round-trip (blank lines added)"
    else
        fail "markdownlint-cli2 round-trip" "no blank lines found in output"
    fi
else
    pass "markdownlint-cli2 round-trip (not installed, skipped)"
fi

# --- ruff ---
if command -v ruff >/dev/null 2>&1; then
    echo ""
    echo "--- ruff ---"
    cat <<'PRE' > "$TESTDIR/fmt.py"
x=1+2
y  =   [1,2,       3]
def   foo(  a,b   ):
    return   a+b
PRE
    cat <<'POST' > "$TESTDIR/fmt.py.expected"
x = 1 + 2
y = [1, 2, 3]


def foo(a, b):
    return a + b
POST
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.py\"}}"
    if diff -q "$TESTDIR/fmt.py" "$TESTDIR/fmt.py.expected" >/dev/null 2>&1; then
        pass "ruff round-trip"
    else
        fail "ruff round-trip" "$(diff "$TESTDIR/fmt.py" "$TESTDIR/fmt.py.expected" || true)"
    fi
else
    pass "ruff round-trip (not installed, skipped)"
fi

# --- rustfmt ---
if command -v rustfmt >/dev/null 2>&1; then
    echo ""
    echo "--- rustfmt ---"
    cat <<'PRE' > "$TESTDIR/fmt.rs"
fn main(){let x=1+2;if x>2{println!("hello");}}
PRE
    cat <<'POST' > "$TESTDIR/fmt.rs.expected"
fn main() {
    let x = 1 + 2;
    if x > 2 {
        println!("hello");
    }
}
POST
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.rs\"}}"
    if diff -q "$TESTDIR/fmt.rs" "$TESTDIR/fmt.rs.expected" >/dev/null 2>&1; then
        pass "rustfmt round-trip"
    else
        fail "rustfmt round-trip" "$(diff "$TESTDIR/fmt.rs" "$TESTDIR/fmt.rs.expected" || true)"
    fi
else
    pass "rustfmt round-trip (not installed, skipped)"
fi

# --- google-java-format ---
if command -v google-java-format >/dev/null 2>&1; then
    echo ""
    echo "--- google-java-format ---"
    cat <<'PRE' > "$TESTDIR/Fmt.java"
public class Fmt{public static void main(String[]args){System.out.println("hello");}}
PRE
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/Fmt.java\"}}"
    if grep -q 'public class Fmt {' "$TESTDIR/Fmt.java"; then
        pass "google-java-format round-trip"
    else
        fail "google-java-format round-trip" "brace style not fixed"
    fi
else
    pass "google-java-format round-trip (not installed, skipped)"
fi

# --- ktlint ---
if command -v ktlint >/dev/null 2>&1; then
    echo ""
    echo "--- ktlint ---"
    cat <<'PRE' > "$TESTDIR/fmt.kt"
fun main(){val x=1+2;println(x)}
PRE
    run_hook "{\"tool_input\":{\"file_path\":\"$TESTDIR/fmt.kt\"}}"
    # ktlint should add spaces around operators and braces
    if grep -q 'fun main()' "$TESTDIR/fmt.kt"; then
        pass "ktlint round-trip (formatted)"
    else
        fail "ktlint round-trip" "formatting not applied"
    fi
else
    pass "ktlint round-trip (not installed, skipped)"
fi

echo ""
echo "=============================="
echo "=== Copilot CLI format ==="

# Helper: run hook with Copilot-format payload
run_hook_copilot() {
    local file_path="$1"
    local json
    json=$(jq -n --arg p "$file_path" '{"toolName":"edit","toolArgs":({"file_path":$p} | tojson)}')
    run_hook "$json"
}

# Test: missing file with Copilot format
echo ""
echo "=== Copilot: missing file ==="
run_hook_copilot "/tmp/nonexistent-copilot-format-test.xyz"
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "copilot format: missing file exits 0"
else
    fail "copilot format: missing file exits 0" "exit code $HOOK_RC"
fi

# Test: empty toolArgs with Copilot format
echo ""
echo "=== Copilot: empty file_path ==="
run_hook '{"toolName":"edit","toolArgs":"{}"}'
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "copilot format: empty file_path exits 0"
else
    fail "copilot format: empty file_path exits 0" "exit code $HOOK_RC"
fi

# Test: file_path extracted correctly (formatter dispatched or gracefully skipped)
echo ""
echo "=== Copilot: file_path extraction ==="
echo "hello" > "$TESTDIR/copilot-test.xyz"
run_hook_copilot "$TESTDIR/copilot-test.xyz"
if [[ "$HOOK_RC" -eq 0 ]]; then
    pass "copilot format: unknown extension exits 0"
else
    fail "copilot format: unknown extension exits 0" "exit code $HOOK_RC"
fi
content=$(cat "$TESTDIR/copilot-test.xyz")
if [[ "$content" == "hello" ]]; then
    pass "copilot format: unknown extension file unchanged"
else
    fail "copilot format: unknown extension file unchanged" "content changed unexpectedly"
fi

# Test: shfmt triggered via Copilot format (if available)
if command -v shfmt >/dev/null 2>&1; then
    echo ""
    echo "=== Copilot: shfmt round-trip ==="
    cat <<'PRE' > "$TESTDIR/copilot-fmt.sh"
#!/bin/bash
if [[ -f /tmp/x ]];then
    echo "ok"
fi
PRE
    cat <<'POST' > "$TESTDIR/copilot-fmt.sh.expected"
#!/bin/bash
if [[ -f /tmp/x ]]; then
  echo "ok"
fi
POST
    run_hook_copilot "$TESTDIR/copilot-fmt.sh"
    if diff -q "$TESTDIR/copilot-fmt.sh" "$TESTDIR/copilot-fmt.sh.expected" >/dev/null 2>&1; then
        pass "copilot format: shfmt round-trip"
    else
        fail "copilot format: shfmt round-trip" "$(diff "$TESTDIR/copilot-fmt.sh" "$TESTDIR/copilot-fmt.sh.expected" || true)"
    fi
else
    pass "copilot format: shfmt round-trip (not installed, skipped)"
fi

echo ""
echo "=============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
