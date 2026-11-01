---
name: questions
description: "Show the parked questions awaiting the user's answer in this session."
disable-model-invocation: true
allowed-tools: Bash
---

# Show parked questions

Run the tracker for this session and show the output to the user verbatim. The session id and the exact command prefix are in the SessionStart context ("Inbox tracker is active for this session").

```bash
<tracker path> --session <session id> list --kind question --full
```

- If it prints nothing, say there is nothing open.
- Do not summarize, reorder, or renumber. The Q- and D-numbers are stable IDs the user will refer to.
- Do not answer or resolve anything here; this skill is read-only.
