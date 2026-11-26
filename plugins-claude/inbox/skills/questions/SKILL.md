---
name: questions
description: "Interactive one-by-one pass over the open parked questions, one AskUserQuestion each, recording every answer."
when_to_use: "Use when the user wants to clear the pending questions quickly by picking options. Not for free-form discussion (answer) or for decisions too (triage)."
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# Answer parked questions interactively

The questions-only variant of `/inbox:triage`: same one-by-one
`AskUserQuestion` walk, but decisions and followups are not part of it. The
session id and the exact command prefix are in the SessionStart context
("Inbox tracker is active for this session").

1. Load the open questions as JSON so nothing is truncated:
   `<tracker path> --session <session id> list --kind question --json`. If there
   are none, say there is nothing open and stop.
2. **One `AskUserQuestion` call per question**, in Q order:
   - `question`: the question title, then the context in one or two lines.
   - `header`: the Q-number (for example `Q2`).
   - The recommendation (`--recommend`, usually an option letter) is already
     one of `options`: move it to the front, labelled `(Recommended)`, with a
     description of why. Do not list it a second time. Then the remaining
     alternatives, at most 4 options in total including the recommended one;
     mention any extras in the question text. The built-in "Other" is the
     free-input path.
   - If there is no recommendation, list the options as given.
   - `AskUserQuestion` needs 2 to 4 options. If fewer than 2 remain, add a
     neutral "Skip for now" option.
   - Act on the answer (do the work or record the choice), then
     `<tracker path> --session <session id> answer Q<n>` immediately.
3. If the user declines or skips a question, leave it open; never `answer` one
   they did not settle. For free-form discussion or merging duplicates, point
   to `/inbox:answer` (chat variant).
4. Finish with `count --kind question` and tell the user how many remain.
