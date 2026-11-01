---
name: answer
description: "Walk through the parked questions with the user in chat and record each answer."
disable-model-invocation: true
allowed-tools: Bash
---

# Answer parked questions

Work through the open questions with the user **in chat** (not with
`AskUserQuestion`). The session id and the exact command prefix are in the SessionStart context ("Inbox tracker is active for this session").

1. Load them: `<tracker path> --session <session id> list --kind question --full`.
   If empty, say so and stop.
2. Merge duplicates first. If two entries ask the same thing, keep the better
   one (`update <id>` to fold in anything the other had) and `answer` the
   duplicate. Tell the user what you merged.
3. Present the open questions with their stable Q-numbers, context, options and
   recommendation. Do not renumber.
4. Let the user answer in their own words, in any order, and ask follow-ups
   freely. Refining a question with the user is expected.
5. As soon as a question is genuinely resolved, record it:
   `<tracker path> --session <session id> answer Q<n>`. Then act on the answer.
6. Questions the user skips or defers stay open. Never `answer` one the user has
   not resolved.
7. Finish by running `count --kind question` and telling the user how many remain.
