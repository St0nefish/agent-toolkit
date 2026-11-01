---
name: confirm
description: "Review the decisions made on a default with the user in chat; accept, change, or defer each."
disable-model-invocation: true
allowed-tools: Bash
---

# Confirm recorded decisions

Review the open decisions with the user **in chat** (not with
`AskUserQuestion`). These are choices already made on a default; the work
proceeded. The session id and the exact command prefix are in the SessionStart context ("Inbox tracker is active for this session").

1. Load them: `<tracker path> --session <session id> list --kind decision --full`.
   If empty, say so and stop.
2. Present each with its stable D-number: what was chosen, the alternatives
   considered, and why.
3. For each one the user decides on:
   - **Accept**: `<tracker path> --session <session id> resolve D<n>`.
   - **Change or reject**: make the adjustment to the work first, then
     `<tracker path> --session <session id> resolve D<n>`, telling the user what changed.
4. Decisions the user defers or skips stay open. Never `resolve` one the user
   has not settled.
5. Finish by running `count --kind decision` and telling the user how many remain.
