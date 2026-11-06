---
name: triage
description: "Interactive one-by-one pass over the inbox: answer each parked question, then approve or change each recorded decision, using AskUserQuestion."
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# Triage the inbox

An interactive walk through everything open. This skill deliberately uses
`AskUserQuestion` (the other inbox skills work in chat). The session id and the
exact command prefix are in the SessionStart context ("Inbox tracker is active
for this session").

1. Load both kinds as JSON so nothing is truncated:
   `<tracker path> --session <session id> list --json`. If both are empty, say
   so and stop. Followups (F-numbers) are not part of this pass; if only
   followups are open, say so and point to `/inbox:followups`.
2. **Questions first, one `AskUserQuestion` call per question**, in Q order:
   - `question`: the question title, then the context in one or two lines.
   - `header`: the Q-number (for example `Q2`).
   - First option: the recommendation, labelled `(Recommended)`, with a
     description of why. Then the alternatives from `options` (at most 3 in
     total after the recommended one; mention any extras in the question text).
     The built-in "Other" is the free-input path.
   - If there is no recommendation, list the options as given.
   - Act on the answer (do the work or record the choice), then
     `<tracker path> --session <session id> answer Q<n>` immediately.
3. **Then decisions, also one call per decision**, in D order:
   - `question`: the decision title, what was chosen, and a one-line context.
   - `header`: the D-number.
   - First option: `Approve: <chosen>` labelled `(Recommended)`. Then the
     considered alternatives as options (at most 3). "Other" is for a comment
     or a different answer.
   - Approve: `<tracker path> --session <session id> resolve D<n>`.
   - Alternative or Other: make that change to the work first, tell the user
     what changed, then `resolve D<n>`.
4. If the user declines or skips an item, leave it open; never `answer` or
   `resolve` something they did not settle.
5. Finish with `count --kind question` and `count --kind decision` and tell the
   user how many of each remain.
