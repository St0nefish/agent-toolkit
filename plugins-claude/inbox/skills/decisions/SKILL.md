---
name: decisions
description: "Show, read-only, the decisions the agent made on a default that the user has not reviewed yet."
when_to_use: "Use when the user asks what was decided or assumed this session. Not for questions or followups (show) or for approving decisions (confirm)."
disable-model-invocation: true
allowed-tools: Bash
---

# Show recorded decisions

Current output of the tracker for this session (injected by the harness, not a tool call):

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox --session ${CLAUDE_SESSION_ID} list --kind decision --format md`

Reply with that output verbatim as markdown (not inside a code block) in your message, so the user sees it without expanding anything.

- If the output above is empty, say there is nothing open.
- Do not summarize, reorder, or renumber. The Q- and D-numbers are stable IDs the user will refer to.
- Do not answer or resolve anything here; this skill is read-only.
