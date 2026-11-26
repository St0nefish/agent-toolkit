---
name: show
description: "Show, read-only, everything open in this session's inbox: parked questions, recorded decisions and logged followups."
when_to_use: "Use when the user asks what is in the inbox or what is pending. Not for answering or resolving items."
disable-model-invocation: true
allowed-tools: Bash
---

# Show the inbox

Current output of the tracker for this session (injected by the harness, not a tool call):

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox --session ${CLAUDE_SESSION_ID} list --format md`

Reply with that output verbatim as markdown (not inside a code block) in your message, so the user sees it without expanding anything.

- If the output above is empty, say there is nothing open.
- Do not summarize, reorder, or renumber. The Q- and D-numbers are stable IDs the user will refer to.
- Do not answer or resolve anything here; this skill is read-only.
