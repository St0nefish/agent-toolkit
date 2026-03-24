---
disable-model-invocation: true
name: analyze-sessions
description: >-
  Detect when the user asks about workflow patterns, friction points, automation
  opportunities, or time loss in their Claude Code usage. Checks session analysis
  state and routes to /session-history-analyzer:analyze for full analysis.
allowed-tools: Bash
---

# Session History Analysis

Triggered when the user asks about workflow patterns, friction, or automation opportunities.

## Trigger phrases

- "analyze my workflow"
- "what patterns do you see"
- "where am I losing time"
- "what should I automate"
- "review my session history"
- "how do I use Claude Code"

## Steps

1. Check current analysis state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh summary
   ```

2. Discover available sessions:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/discover-sessions.sh
   ```

3. Summarize what's available:
   - How many sessions exist across how many projects
   - How many have already been analyzed
   - When the last analysis was run

4. Route to `/session-history-analyzer:analyze` for a full analysis run. Do not attempt to parse sessions directly from this skill.
