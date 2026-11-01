---
name: list
description: "Show the parked questions awaiting the user's answer in this session."
disable-model-invocation: true
allowed-tools: Bash
---

# List parked questions

Run the tracker for this session and show the output to the user verbatim. The
session id and the exact command prefix were given in the SessionStart context
("Parked-question tracker is active for this session").

```bash
<tracker path> --session <session id> list --full
```

- If it prints nothing, say there are no open questions.
- Do not summarize, reorder, or renumber — the Q-numbers are stable IDs the user
  will refer to.
- Do not answer or resolve anything here; this skill is read-only.
