---
disable-model-invocation: true
name: history-status
description: "Show session-history analysis state: last run, and analyzed vs pending session counts per project."
when_to_use: "Use when the user asks whether history analysis is up to date or how many sessions are pending before running history-analyze."
allowed-tools: Bash
---

# Analysis Status

Show the current state of session history analysis.

## Steps

1. Get analysis state summary:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh summary
   ```

2. Discover all available sessions:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/discover-sessions.sh
   ```

3. Cross-reference to compute pending counts per project. Present a status card:

   ```text
   Last analysis: <date or "never">
   Total analyzed: <N> sessions
   Pending: <N> sessions across <N> projects

   Per project:
     <slug>: <analyzed>/<total> sessions
     ...
   ```

4. If there are pending sessions, suggest running `/session-history-analyzer:history-analyze`.
