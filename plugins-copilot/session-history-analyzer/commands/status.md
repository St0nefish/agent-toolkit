---
description: "Show analysis state — analyzed vs pending session counts per project"
allowed-tools: Bash
---

# Analysis Status

Show the current state of session history analysis.

## Steps

1. Get analysis state summary:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/state-manager.sh summary
   ```

2. Discover all available sessions:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/discover-sessions.sh
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

4. If there are pending sessions, suggest running `/session-history-analyzer:analyze`.
