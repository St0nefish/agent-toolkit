#!/usr/bin/env bash
# Tests for hooks/bash-safety/bash-safety.sh — Gradle classifier
# Run from repo root: bash tests/test-bash-safety-gradle.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/bash-safety/bash-safety.sh"

PASS=0 FAIL=0

test_hook() {
  local label="$1" cmd="$2" expected="$3"
  local output json
  json=$(jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
  output=$(echo "$json" | bash "$HOOK" 2>/dev/null) || true
  local decision=""
  if echo "$output" | grep -q '"allow"'; then decision="allow"
  elif echo "$output" | grep -q '"ask"'; then decision="ask"
  else decision="none"
  fi
  if [[ "$decision" == "$expected" ]]; then
    echo "PASS: $label → $decision"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label → got $decision, expected $expected"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Read-only gradle tasks (expect allow) ==="
test_hook "gradle tasks"                    'gradle tasks'                          "allow"
test_hook "gradle tasks --all"              'gradle tasks --all'                    "allow"
test_hook "./gradlew tasks"                 './gradlew tasks'                       "allow"
test_hook "gradlew tasks"                   'gradlew tasks'                         "allow"
test_hook "gradle help"                     'gradle help'                           "allow"
test_hook "gradle projects"                 'gradle projects'                       "allow"
test_hook "gradle properties"               'gradle properties'                     "allow"
test_hook "gradle dependencies"             'gradle dependencies'                   "allow"
test_hook "gradle dependencyInsight"        'gradle dependencyInsight --dependency commons-io' "allow"
test_hook "gradle buildEnvironment"         'gradle buildEnvironment'               "allow"
test_hook "gradle components"               'gradle components'                     "allow"
test_hook "gradle outgoingVariants"         'gradle outgoingVariants'               "allow"
test_hook "gradle resolvableConfigurations" 'gradle resolvableConfigurations'       "allow"
test_hook "gradle --version"                'gradle --version'                      "allow"
test_hook "./gradlew --version"             './gradlew --version'                   "allow"
test_hook "gradle --help"                   'gradle --help'                         "allow"
test_hook "bare gradle"                     'gradle'                                "allow"

echo ""
echo "=== Read-only with project prefix (expect allow) ==="
test_hook "gradle :sub:tasks"               'gradle :sub:tasks'                     "allow"
test_hook "gradle :sub:dependencies"        'gradle :sub:dependencies'              "allow"
test_hook "./gradlew :app:properties"       './gradlew :app:properties'             "allow"
test_hook "gradle :help"                    'gradle :help'                          "allow"

echo ""
echo "=== --dry-run makes any task read-only (expect allow) ==="
test_hook "gradle --dry-run build"          'gradle --dry-run build'                "allow"
test_hook "gradle build --dry-run"          'gradle build --dry-run'                "allow"
test_hook "gradle -m build"                 'gradle -m build'                       "allow"
test_hook "./gradlew --dry-run test"        './gradlew --dry-run test'              "allow"
test_hook "gradle -m clean build"           'gradle -m clean build'                 "allow"

echo ""
echo "=== Read-only with extra flags (expect allow) ==="
test_hook "gradle tasks --info"             'gradle tasks --info'                   "allow"
test_hook "gradle tasks -q"                 'gradle tasks -q'                       "allow"
test_hook "gradle dependencies --configuration runtime" 'gradle dependencies --configuration runtime' "allow"
test_hook "gradle -p /path tasks"           'gradle -p /path tasks'                 "allow"
test_hook "./gradlew --no-daemon tasks"     './gradlew --no-daemon tasks'           "allow"

echo ""
echo "=== Write gradle tasks (expect ask) ==="
test_hook "gradle build"                    'gradle build'                          "ask"
test_hook "./gradlew build"                 './gradlew build'                       "ask"
test_hook "gradle test"                     'gradle test'                           "ask"
test_hook "gradle clean"                    'gradle clean'                          "ask"
test_hook "gradle assemble"                 'gradle assemble'                       "ask"
test_hook "gradle publish"                  'gradle publish'                        "ask"
test_hook "gradle bootRun"                  'gradle bootRun'                        "ask"
test_hook "gradle run"                      'gradle run'                            "ask"
test_hook "gradle check"                    'gradle check'                          "ask"
test_hook "gradle jar"                      'gradle jar'                            "ask"
test_hook "gradle compileJava"              'gradle compileJava'                    "ask"
test_hook "gradle installDist"              'gradle installDist'                    "ask"
test_hook "gradle :app:build"               'gradle :app:build'                     "ask"
test_hook "./gradlew clean build"           './gradlew clean build'                 "ask"
test_hook "gradle generateLock"             'gradle generateLock'                   "ask"

echo ""
echo "=== Mixed read+write tasks (expect ask) ==="
test_hook "gradle tasks build"              'gradle tasks build'                    "ask"
test_hook "gradle dependencies clean"       'gradle dependencies clean'             "ask"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
