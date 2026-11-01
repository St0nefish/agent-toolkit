---
name: park-question
description: "Use when you need a decision or information from the user that you cannot resolve from the request, code, or sensible defaults: park the question in the session tracker instead of writing an 'input needed' banner or asking mid-stream."
user-invocable: false
---

# Park a question

A question for the user goes into the session tracker, not into a banner you
write. The Stop hook shows the "input needed" flag from tracker state, so the
flag is accurate without you restating anything.

The exact command prefix (tracker path and session id) is in the SessionStart
context: "Parked-question tracker is active for this session".

## When to park

- You are blocked on a decision that is genuinely the user's to make.
- Real blockers only — not FYIs, not "let me know if you want X" offers, not
  things a sensible default settles.

## How

```bash
<tracker path> --session <session id> add \
  --title "Short, self-contained title" \
  --context "What you were doing, what you found, why it needs the user" \
  --option "Option A — tradeoff" --option "Option B — tradeoff" \
  --recommend "A, because ..."
```

- Make each question stand alone: the user may read only the list.
- One decision per question.
- If `add` exits 3 ("similar to Q<n>"), do not force it. `update <n>` the existing
  question, or pass `--new` only if it is genuinely a different question.

## After parking

- **Keep working** on everything the question does not block. Parking is not
  stopping.
- Do not write an "INPUT NEEDED" header or restate the question list in your
  messages. The hooks and statusline handle the flag; the user runs
  `/questions:list` to see the details.
- When the user answers in chat, record it right away:
  `<tracker path> --session <session id> answer <id>`. A stale open question
  keeps the flag lit, so a forgotten `answer` is the main failure mode.
