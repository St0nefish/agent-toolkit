# questions

Park questions for the user in a per-session store so "input needed" is a
deterministic flag derived from state, not something the agent has to remember
to write on every message.

## How it works

- **Tracker** (`scripts/questions`, vendored from `utils/questions`): stores open
  questions per session under
  `${XDG_STATE_HOME:-~/.local/state}/claude-questions/<session_id>.json`. IDs are
  monotonic and never reused. `add` rejects near-duplicates of open questions.
- **Stop hook**: when questions are open it prints a one-line flag to the user
  (not the model):
  - `🛑 INPUT NEEDED (N)` — nothing else is running; the session is stuck on you.
  - `⏳ N parked question(s), still working` — background work is still running.
  - Nothing when no questions are open.
- **SessionStart hook**: gives the agent the exact tracker command (with the
  session id), re-injects open questions after `/compact` or `/clear`, and prunes
  state files older than 7 days.
- **UserPromptSubmit hook**: while questions are open, one short line telling the
  agent to record an answer if your prompt provides one.
- The `statusline` plugin shows a `🛑 N` segment and `notify-on-stop` sends an
  "input needed" notification when questions are open.

State is per session: `/clear` starts a fresh list.

## Skills

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `/questions:list` | user-only | Show the open questions (stable Q-numbers) |
| `/questions:answer` | user-only | Walk through them in chat, merge duplicates, record answers |
| `park-question` | model-only | When and how the agent should park a question |

## Tracker CLI

```text
questions --session <id> add --title T [--context C] [--option O]... [--recommend R] [--new]
questions --session <id> update <id> [--title T] [--context C] [--option O]... [--recommend R]
questions --session <id> answer <id>
questions --session <id> list [--full] [--json]
questions --session <id> count
questions prune [--days N]
```

`add` exits 3 when the title is similar to an open question; use `update` or
pass `--new`.
