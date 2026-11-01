---
name: record-decision
description: "Use when you proceed on a default for a key choice the user may want a say in (approach, architecture, naming, scope, assumptions): record it as a decision for later review instead of stopping to ask."
user-invocable: false
---

# Record a decision

When a choice is the user's but you can pick the most likely right answer, do
not block: state the assumption, keep going, and record a decision. Decisions
never light the "input needed" flag and do not stop work.

The exact command prefix (tracker path and session id) is in the SessionStart
context: "Inbox tracker is active for this session".

## When to record

Key decisions only: approach, architecture, naming, scope, or assumptions the
user would plausibly want a say in. Not every trivial edit. If a wrong guess
would be unsafe (destructive, hard to reverse, outward-facing, spends money or
credentials) or information is missing, use `park-question` instead.

## How

```bash
<tracker path> --session <session id> add decision \
  --title "Short, self-contained title" \
  --context "Why you chose this" \
  --option "Alternative A" --option "Alternative B" \
  --chosen "What you went with"
```

- Make each decision stand alone: the user may read only the list.
- If `add` exits 3 ("similar to D<n>"), do not force it. `update D<n>` the
  existing one, or pass `--new` only if it is genuinely different.

## After recording

- Keep working. Decisions are reviewed later via `/inbox:confirm` or at
  session-end.
- If the user redirects you about a decision in chat, adjust the work, then
  `<tracker path> --session <session id> resolve D<n>`, telling the user what changed.
