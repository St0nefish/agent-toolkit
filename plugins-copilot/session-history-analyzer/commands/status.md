---
description: "Show session-history coverage and recent activity by project"
allowed-tools: SQL
---

# Analysis Status

Show the current state of session history available through Copilot CLI's session store.

## Steps

1. Query `session_store` for recent sessions and last-seen timestamps grouped by repository or cwd.

2. Present a status card:

   ```text
   Last session seen: <date or "none">
   Total sessions: <N>
   Recent sessions (30d): <N>

   Per project:
     <repo-or-path>: <count> sessions
     ...
   ```

3. If there is enough history to analyze, suggest running `/session-history-analyzer:analyze`.

## Notes

- In Copilot CLI, prefer the built-in session store over plugin-private state files.
- There is no separate analyzed vs pending registry here; report available history instead.
