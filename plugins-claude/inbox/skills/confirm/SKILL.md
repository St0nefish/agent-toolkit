---
name: confirm
description: "Confirm the decisions made on a default. With no arguments, accept all open decisions; with arguments, apply the user's notes or exclusions."
argument-hint: "[notes, or 'except D3']"
disable-model-invocation: true
allowed-tools: Bash
---

# Confirm recorded decisions

These are choices already made on a default; the work proceeded. Handle them
**in chat** (not with `AskUserQuestion`; `/inbox:triage` is the interactive
one-by-one variant). The session id and the exact command prefix are in the
SessionStart context ("Inbox tracker is active for this session").

Arguments from the user: `$ARGUMENTS`

1. Load them: `<tracker path> --session <session id> list --kind decision --format md`.
   If empty, say so and stop.
2. **No arguments: the user is confirming all of them.** Show the list above as
   markdown (not in a code block), then `resolve D<n>` every open decision.
3. **With arguments**, read them as the user's instructions: a note about a
   specific decision, an exclusion ("except D3"), or a requested change. For
   each decision the user wants changed or rejected, make the adjustment to the
   work first, then `resolve D<n>` and say what changed. Resolve everything the
   arguments do not exclude or contest. Anything the user excluded or deferred
   stays open.
4. Never `resolve` a decision the user has explicitly held back.
5. Finish by running `count --kind decision` and telling the user how many remain.
