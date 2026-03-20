#!/usr/bin/env bash
# parse-session.sh — Extract structured data from one JSONL session file
#
# Args: <jsonl-path>
# Output: single JSON object with session analysis

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: parse-session.sh <jsonl-path>" >&2
  exit 2
fi

JSONL_PATH="$1"

if [[ ! -f "$JSONL_PATH" ]]; then
  echo "File not found: $JSONL_PATH" >&2
  exit 1
fi

SESSION_ID=$(basename "$JSONL_PATH" .jsonl)

# Single-pass jq extraction — filters to user/assistant/system records only
jq -s --arg sid "$SESSION_ID" '
  # Filter to relevant record types
  [.[] | select(.type == "user" or .type == "assistant" or .type == "system")] as $records |

  # Timestamps for duration
  [$records[] | .timestamp // empty | select(. != null)] as $timestamps |
  ($timestamps | if length > 0 then (first | sub("\\.[0-9]+Z$"; "Z")) else null end) as $started |
  ($timestamps | if length > 0 then (last | sub("\\.[0-9]+Z$"; "Z")) else null end) as $ended |

  # User prompts — extract text from string or array content, skip pure tool_result turns
  [
    $records[] | select(.type == "user") |
    if (.message.content | type) == "string" then
      .message.content
    elif (.message.content | type) == "array" then
      [.message.content[] | select(.type == "text") | .text] |
      if length > 0 then join("\n") else empty end
    else
      empty
    end
  ] as $user_prompts |

  # Tool counts — aggregate tool_use blocks from assistant records
  [
    $records[] | select(.type == "assistant") |
    .message.content // [] | .[] |
    select(.type == "tool_use") | .name
  ] | group_by(.) | map({(.[0]): length}) | add // {} |
  to_entries | sort_by(-.value) | from_entries
  as $tool_counts |

  # Turn count — number of user messages with actual content
  [$records[] | select(.type == "user")] | length as $turn_count |

  # Compaction count — compact_boundary system records
  [$records[] | select(.type == "system" and .subtype == "compact_boundary")] | length as $compaction_count |

  # Friction indicators
  (
    # Hook blocks — look for hook blocking messages in tool_result content
    [
      $records[] | select(.type == "user") |
      .message.content // [] |
      if type == "array" then
        .[] | select(.type == "tool_result") |
        .content // "" |
        if type == "string" then . else (if type == "array" then ([.[] | select(.type == "text") | .text] | join("\n")) else "" end) end
      else
        ""
      end |
      select(test("hook blocked|was blocked|permission denied|not allowed"; "i"))
    ] | length
  ) as $hook_blocks |
  (
    # Retries — look for repeated identical tool calls (approximation)
    0
  ) as $retries |
  {hook_blocks: $hook_blocks, retries: $retries, compactions: $compaction_count} as $friction |

  # Workflow signals
  (
    [$records[] | select(.type == "assistant") |
      .message.content // [] | .[] |
      select(.type == "tool_use") | .name] |
    {
      uses_agents: (any(. == "Agent") // false),
      uses_web: (any(. == "WebFetch" or . == "WebSearch") // false),
      uses_mcp: (any(startswith("mcp__")) // false)
    }
  ) as $workflow_signals |

  # Git branch from system records
  (
    [$records[] | select(.type == "system" or .type == "user") | .gitBranch // empty] |
    if length > 0 then first else null end
  ) as $git_branch |

  {
    session_id: $sid,
    started_at: $started,
    ended_at: $ended,
    turn_count: $turn_count,
    user_prompts: $user_prompts,
    tool_counts: $tool_counts,
    compaction_count: $compaction_count,
    friction_indicators: $friction,
    workflow_signals: $workflow_signals,
    git_branch: $git_branch
  }
' "$JSONL_PATH"
