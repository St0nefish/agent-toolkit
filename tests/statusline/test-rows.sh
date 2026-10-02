#!/usr/bin/env bash
# test-rows.sh — Tests for statusline multi-row layout, legacy `segments`
# fallback, project-name `dir` segment, and git branch middle-truncation.
#
# Usage: bash tests/statusline/test-rows.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../../plugins-claude/statusline/scripts/statusline.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"

# Hermetic usage: a stub credentials file plus a fresh usage cache means the
# usage/extra segments never touch the real credentials or the network.
export HOME="$TMP/home"
mkdir -p "$HOME/.claude" "$XDG_CACHE_HOME/claude-statusline"
printf '{"claudeAiOauth":{"accessToken":"t"}}' >"$HOME/.claude/.credentials.json"
jq -nc --arg r "$(date -u -d "+3 hours" +%Y-%m-%dT%H:%M:%SZ)" '{five_hour:{utilization:4,resets_at:$r},seven_day:{utilization:40,resets_at:$r}}' \
  >"$XDG_CACHE_HOME/claude-statusline/usage.json"
CFG="$XDG_CONFIG_HOME/claude-statusline/config.json"
mkdir -p "$(dirname "$CFG")"

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

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Non-git project dirs keep the output independent of the host repo state.
PROJ="$TMP/work/my-project"
mkdir -p "$PROJ/sub/dir"
STDIN=$(jq -nc --arg cwd "$PROJ/sub/dir" --arg proj "$PROJ" \
  '{model:{display_name:"M"},context_window:{used_percentage:7},workspace:{current_dir:$cwd,project_dir:$proj}}')

# render <config-json> → ANSI-stripped statusline output
render() {
  printf '%s' "$1" >"$CFG"
  printf '%s\n' "$STDIN" | bash "$STATUSLINE" | strip_ansi
}

# ===== truncate_middle =====
echo "── truncate_middle ──"
# shellcheck source=/dev/null
source "$STATUSLINE" </dev/null

check "shorter than max → unchanged" "feat/x" "$(truncate_middle feat/x 40)"
check "max 0 → disabled" "abcdefghij" "$(truncate_middle abcdefghij 0)"
check "over max → ellipsized to exactly max chars" "10" \
  "$(truncate_middle abcdefghijklmnopqrstuvwxyz 10 | wc -m | tr -d ' \n' | awk '{print $1-0}')"
check "max 2 → no whole-string tail leak" "f…" "$(truncate_middle feat/long-branch 2)"
check "non-integer max → unchanged" "feat/long-branch" "$(truncate_middle feat/long-branch abc)"
check "keeps prefix and tail" "abcde…vwxyz" "$(truncate_middle abcdefghijklmnopqrstuvwxyz 11)"

# ===== rows =====
echo "── rows ──"

OUT=$(render '{"rows":[["user","dir"],["model","context"]],"context_style":"text"}')
check "two rows → two lines" "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "row 1 content" "$USER | ⌂ my-project" "$(printf '%s\n' "$OUT" | sed -n 1p)"
check "row 2 content" "M$(printf '%*s' $((${#USER} - 1)) '') | Ctx 7%" "$(printf '%s\n' "$OUT" | sed -n 2p)"

OUT=$(render '{"rows":[["git"],["model"]]}')
check "row with all segments hidden is skipped" "M" "$OUT"

OUT=$(render '{"segments":["dir","model"]}')
check "legacy segments → single row" "⌂ my-project | M" "$OUT"

OUT=$(render '{"segments":["dir"],"rows":[["model"]]}')
check "rows wins over legacy segments" "M" "$OUT"

OUT=$(render '{}')
check "default config → two rows" "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

# ===== alignment =====
echo "── align ──"

# Row 1 col 1 is "$USER" (variable width); row 2 col 1 is "M". Separators must
# land in the same column on both rows when aligned.
OUT=$(render '{"rows":[["user","dir"],["model","context"]],"context_style":"text"}')
check "aligned → first separator in same column" \
  "$(printf '%s\n' "$OUT" | sed -n 1p | awk '{print index($0,"|")}')" \
  "$(printf '%s\n' "$OUT" | sed -n 2p | awk '{print index($0,"|")}')"

OUT=$(render '{"rows":[["user","dir"],["model","context"]],"context_style":"text","align":false}')
check "align=false → no padding" "M | Ctx 7%" "$(printf '%s\n' "$OUT" | sed -n 2p)"

OUT=$(render '{"rows":[["user","dir"],["model","context"]],"context_style":"text"}')
check "last cell on a row is not padded" "M$(printf '%*s' $((${#USER} - 1)) '') | Ctx 7%" \
  "$(printf '%s\n' "$OUT" | sed -n 2p)"

# ===== context style =====
echo "── context_style ──"

# Display width (chars, not bytes) of everything up to and including the 2nd
# separator, so a stretched bar must line up with the project cell above it.
col2_end() { printf '%s' "$1" | cut -d'|' -f1,2 | LC_ALL=C.UTF-8 wc -m | tr -d ' '; }

OUT=$(render '{"rows":[["model","context"]],"context_style":"bar"}')
check "last cell on its row → default bar width (10) + pct" "10" \
  "$(printf '%s' "$OUT" | grep -o '[█━]' | wc -l | tr -d ' ')"

OUT=$(render '{"rows":[["context"]],"context_style":"icon"}')
check "icon style → glyph + pct" "○ 7%" "$OUT"

OUT=$(render '{"rows":[["context"]],"context_style":"text","label_style":"long"}')
check "text style → labelled" "Context 7%" "$OUT"

# ===== dir style =====
echo "── dir_style ──"

OUT=$(render '{"rows":[["dir"]]}')
check "default → project name only, even from a subdir" "⌂ my-project" "$OUT"

OUT=$(render '{"rows":[["dir"]],"dir_style":"path"}')
check "path style → legacy abbreviated path" "⌂ my-project/s/dir" "$OUT"

# ===== icons & worktree marker =====
echo "── icons / worktree ──"

OUT=$(render '{"rows":[["dir"]],"dir_icon":""}')
check "dir_icon empty → no icon" "my-project" "$OUT"

OUT=$(render '{"rows":[["dir"]],"dir_icon":">"}')
check "dir_icon custom" "> my-project" "$OUT"

# Real git repo + linked worktree for marker and git icon checks.
MAIN="$TMP/wt/main-repo"
LINKED="$TMP/wt/linked"
git init -q -b master "$MAIN"
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$LINKED" -b feat/x

render_at() {
  local dir="$1" cfg="$2"
  printf '%s' "$cfg" >"$CFG"
  jq -nc --arg d "$dir" '{model:{display_name:"M"},workspace:{current_dir:$d,project_dir:$d}}' |
    bash "$STATUSLINE" | strip_ansi
}

check "main checkout → no worktree marker" "⌂ main-repo" "$(render_at "$MAIN" '{"rows":[["dir"]]}')"
check "linked worktree → marker after main repo name" "⌂ main-repo⧉" "$(render_at "$LINKED" '{"rows":[["dir"]]}')"
check "worktree_marker empty → disabled" "⌂ main-repo" "$(render_at "$LINKED" '{"rows":[["dir"]],"worktree_marker":""}')"
check "git icon precedes branch" "⎇ feat/x" "$(render_at "$LINKED" '{"rows":[["git"]]}')"
check "git_icon empty → bare branch" "feat/x" "$(render_at "$LINKED" '{"rows":[["git"]],"git_icon":""}')"

# ===== context bar fits the project column =====
echo "── context bar fit ──"

# Project cell "⌂ a-long-project" is 16 wide; the bar cell is bar + " 0%" (3),
# so the stretched bar is 13. A different project name must give a different bar.
LONG="$TMP/wt/a-long-project"
git init -q -b master "$LONG"
git -C "$LONG" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
ROWS_CFG='{"rows":[["user","dir","git"],["model","context","git"]]}'

OUT=$(render_at "$LONG" "$ROWS_CFG")
check "bar width tracks project name length" "13" \
  "$(printf '%s\n' "$OUT" | sed -n 2p | grep -o '[█━]' | wc -l | tr -d ' ')"
check "stretched bar keeps column-2 separators aligned" \
  "$(col2_end "$(printf '%s\n' "$OUT" | sed -n 1p)")" \
  "$(col2_end "$(printf '%s\n' "$OUT" | sed -n 2p)")"

OUT=$(render_at "$MAIN" "$ROWS_CFG")
check "shorter project name → minimum bar (8)" "8" \
  "$(printf '%s\n' "$OUT" | sed -n 2p | grep -o '[█━]' | wc -l | tr -d ' ')"

# ===== context bar size config =====
echo "── context bar config ──"

bar_cells() { printf '%s\n' "$1" | sed -n 2p | grep -o '[█━]' | wc -l | tr -d ' '; }
ROWS_JSON='"rows":[["user","dir","git"],["model","context","git"]]'

check "context_bar_min raises the floor" "12" \
  "$(bar_cells "$(render_at "$MAIN" "{$ROWS_JSON,\"context_bar_min\":12}")")"
check "context_bar_max caps the stretch" "9" \
  "$(bar_cells "$(render_at "$LONG" "{$ROWS_JSON,\"context_bar_max\":9}")")"
check "max below min → min wins" "12" \
  "$(bar_cells "$(render_at "$LONG" "{$ROWS_JSON,\"context_bar_min\":12,\"context_bar_max\":5}")")"
check "context_bar_default sizes a last-cell bar" "15" \
  "$(bar_cells "$(render_at "$MAIN" '{"rows":[["user"],["model","context"]],"context_bar_default":15}')")"
check "non-numeric size ignored" "13" \
  "$(bar_cells "$(render_at "$LONG" "{$ROWS_JSON,\"context_bar_max\":\"wide\"}")")"
check "zero size ignored" "13" \
  "$(bar_cells "$(render_at "$LONG" "{$ROWS_JSON,\"context_bar_min\":0}")")"
check "align=false → default size, no stretch" "10" \
  "$(bar_cells "$(render_at "$LONG" "{$ROWS_JSON,\"align\":false}")")"

# ===== extra usage =====
echo "── extra usage ──"

# A fresh usage cache lets seg_usage/seg_extra render without the network. The
# access-token check needs a credentials file, so point HOME at a stub.
FUTURE=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%M:%SZ)
jq -nc --arg r "$FUTURE" \
  '{five_hour:{utilization:100,resets_at:$r},seven_day:{utilization:40,resets_at:$r},extra_usage:{is_enabled:true,used_credits:1250,monthly_limit:5000,utilization:25}}' \
  >"$XDG_CACHE_HOME/claude-statusline/usage.json"

render_usage() {
  printf '%s' "$1" >"$CFG"
  printf "%s\n" "$STDIN" | bash "$STATUSLINE" | strip_ansi
}

OUT=$(render_usage '{"rows":[["usage","extra"]],"align":false}')
check "extra appears after usage with spend/limit" "true" \
  "$([[ "$OUT" == *" | Ex \$12.50/\$50.00" ]] && echo true || echo false)"
OUT=$(render_usage '{"rows":[["usage"],["extra"]]}')
check "extra on its own row" "Ex \$12.50/\$50.00" "$(printf '%s\n' "$OUT" | sed -n 2p)"
OUT=$(render_usage '{"rows":[["usage"]],"label_style":"long"}')
check "usage renders both windows with icons" "true" \
  "$([[ "$OUT" == "◷ 100% "*" · ▦ 40% "* ]] && echo true || echo false)"
OUT=$(render_usage '{"rows":[["usage"]],"session_icon":"","week_icon":""}')
check "empty icons fall back to 5h/7d text" "true" \
  "$([[ "$OUT" == "5h 100% ⟳"*" · 7d 40% ⟳"* ]] && echo true || echo false)"
OUT=$(render_usage '{"rows":[["usage"]],"usage_extra":true}')
check "usage_extra appends extra to the usage segment" "true" \
  "$([[ "$OUT" == *" · ▦ 40% "*" · Ex \$12.50/\$50.00" ]] && echo true || echo false)"
OUT=$(render_usage '{"rows":[["usage","extra"]],"usage_extra":true,"align":false}')
check "usage_extra → standalone extra suppressed (no duplicate)" "1" \
  "$(printf '%s' "$OUT" | grep -o 'Ex \$' | wc -l | tr -d ' ')"
OUT=$(render_usage '{}')
check "default layout → extra on its own third row" "Ex \$12.50/\$50.00" "$(printf '%s\n' "$OUT" | sed -n 3p)"
OUT=$(render_usage '{"usage_extra":true}')
check "default layout + usage_extra → two rows, extra inline" "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
jq '.extra_usage.used_credits=0' "$XDG_CACHE_HOME/claude-statusline/usage.json" >"$TMP/u.json" && mv "$TMP/u.json" "$XDG_CACHE_HOME/claude-statusline/usage.json"
OUT=$(render_usage '{"rows":[["usage","extra"]],"align":false}')
check "extra hidden when nothing spent" "false" "$([[ "$OUT" == *Ex* ]] && echo true || echo false)"

# ===== Summary =====
echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
