---
name: respond
description: "Work through the inbox in chat: answer the parked questions first, then review and resolve the recorded decisions."
when_to_use: "Use when the user wants to go over both questions and decisions conversationally. Not for followups, and not the AskUserQuestion pass (triage)."
disable-model-invocation: true
allowed-tools: Bash
---

# Respond to the inbox

Handle both kinds of item **in chat** (not with `AskUserQuestion`). The session id and the exact command prefix are in the SessionStart context ("Inbox tracker is active for this session").

1. Questions first (the `/inbox:answer` skill is user-only, so follow these steps here):
   load with `list --kind question --full`, merge duplicates (`update` the keeper,
   `answer` the duplicate), present with stable Q-numbers, and run
   `answer Q<n>` as each one is genuinely resolved. Skipped ones stay open.
2. Then offer the decisions (same reason, inline): load with
   `list --kind decision --full`, present each D-number, and for each the user
   settles, make any requested change to the work first, then `resolve D<n>`.
3. If the user says to defer decisions, leave them open and move on.
4. Finish with `count --kind question` and `count --kind decision` and tell
   the user how many of each remain.
