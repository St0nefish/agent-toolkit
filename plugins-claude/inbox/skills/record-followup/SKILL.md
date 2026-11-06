---
name: record-followup
description: "Use when you notice work worth doing before the session wraps up but not now (out of scope, deferred, docs or tests not done, a bug or issue to file): log it as a followup in the session inbox so it survives /compact and /clear."
user-invocable: false
---

# Log a followup

A followup is a note to your future self (and the user): something worth
considering before this session ends that you are not doing right now. It lives
in the inbox state file, so the SessionStart hook re-injects it after `/compact`
or `/clear`. Followups are quiet: they never raise the "input needed" flag and
never stop work.

The exact command prefix (tracker path and session id) is in the SessionStart
context: "Inbox tracker is active for this session".

## When to log

- You noticed something out of scope (an unrelated bug, a smell, a flaky test).
- You deferred part of the work on purpose.
- Adjacent work is unfinished: docs not updated, a test not written, a version
  not bumped, a call site or mirror not yet changed.
- An issue is worth filing but you were not asked to file it.

## When not to log

- You are blocked on the user: use `park-question`.
- It is a choice you made on a default: use `record-decision`.
- You will do it in the next minute: just do it.
- Trivial edits and anything already tracked by an open item.

## How

```bash
<tracker path> --session <session id> add followup \
  --title "Short imperative note" \
  --context "Where it is, why it matters, what doing it would involve"
```

- Titles are short imperative notes, not questions ("Add test for empty
  options", "File issue: flaky statusline poll").
- Make each followup stand alone: it may be read after a `/compact`.
- If `add` exits 3 ("similar to F<n>"), do not force it. `update F<n>` the
  existing one, or pass `--new` only if it is genuinely different.

## After logging

- Keep working. Do not announce each followup.
- When you finish one, close it: `<tracker path> --session <session id> done F<n>`.
- Open followups are reviewed with `/inbox:followups` and at session-end.
