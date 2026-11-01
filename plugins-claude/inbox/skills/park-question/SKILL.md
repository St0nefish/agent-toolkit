---
name: park-question
description: "Use when you are genuinely blocked on the user (a guess would be unsafe, or information is missing): park the question in the session inbox instead of writing an 'input needed' banner or asking mid-stream."
user-invocable: false
---

# Park a question

A question goes into the session inbox, not into a banner you write. The Stop
hook shows the "input needed" flag from tracker state.

The exact command prefix (tracker path and session id) is in the SessionStart
context: "Inbox tracker is active for this session".

## When to park

Default to proceeding. Park a question only when:

- a guess would be unsafe: destructive, hard to reverse, outward-facing, or
  spends money or credentials; or
- information is genuinely missing and cannot be found in the request or code.

If you can proceed on a reasonable default, do that and use the
`record-decision` skill instead. Not FYIs, not "let me know if you want X".

## How

```bash
<tracker path> --session <session id> add question \
  --title "Short, self-contained title" \
  --context "What you were doing, what you found, why it needs the user" \
  --option "Option A: tradeoff" --option "Option B: tradeoff" \
  --recommend "A, because ..."
```

- Make each question stand alone: the user may read only the list.
- One decision per question.
- If `add` exits 3 ("similar to Q<n>"), do not force it. `update Q<n>` the
  existing question, or pass `--new` only if it is genuinely different.

## After parking

- **Keep working** on everything the question does not block; hold only the
  affected work.
- Never write an "INPUT NEEDED" header or restate the list. The hooks and
  statusline show the flag; the user runs `/inbox:questions` for details.
- When the user answers in chat, record it right away:
  `<tracker path> --session <session id> answer Q<n>`. A stale open question
  keeps the flag lit.
