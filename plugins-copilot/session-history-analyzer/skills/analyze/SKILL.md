---
user-invocable: false
name: analyze-sessions
description: >-
  Detect when the user asks about workflow patterns, friction points, automation
  opportunities, or time loss in their Copilot CLI usage. Checks session-store
  coverage and routes to /session-history-analyzer:analyze for full analysis.
allowed-tools: SQL
---

# Session History Analysis

Triggered when the user asks about workflow patterns, friction, or automation opportunities.

## Trigger phrases

- "analyze my workflow"
- "what patterns do you see"
- "where am I losing time"
- "what should I automate"
- "review my session history"
- "how do I use Copilot CLI"

## Steps

1. Check available history in `session_store`:
   - how many sessions exist across how many repos or working directories
   - when the most recent matching session was recorded
   - whether there is enough history to justify a deeper analysis

2. Summarize what's available:
   - session counts
   - project spread
   - recency

3. Route to `/session-history-analyzer:analyze` for a full analysis run. Do not attempt to synthesize the full workflow report from this skill alone.
