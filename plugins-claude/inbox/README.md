# inbox

A per-session inbox with two kinds of item, so "input needed" is a
deterministic flag derived from state rather than something the agent has to
remember to write.

- **Question** (`Q<n>`): blocks on you. Drives the input-needed flag.
- **Decision** (`D<n>`): the agent already proceeded on a reasonable default (a
  key choice you may want a say in). You review it later. Decisions never drive
  the flag.

The policy the agent is taught: default to proceeding. When a choice is yours,
pick the most likely answer, state the assumption, keep going, and record a
decision. Park a question only when a guess would be unsafe (destructive, hard to
reverse, outward-facing, spends money or credentials) or information is
genuinely missing, and hold only the affected work.

## How it works

- **Tracker** (`scripts/inbox`, vendored from `utils/inbox`): stores open items
  per session. IDs are monotonic per kind and never reused. `add` rejects
  near-duplicates of open items of the same kind.
- **Stop hook**: only open questions matter.
  - `🛑 INPUT NEEDED (N)`: nothing else is running; the session is stuck on you.
  - `⏳ N parked question(s), still working`: background work is still running.
  - Nothing when no questions are open. Decisions are quiet.
- **SessionStart hook**: gives the agent the exact tracker commands (with the
  session id) and the policy, re-injects open items after `/compact` or
  `/clear`, and prunes state files older than 7 days.
- **UserPromptSubmit hook**: while questions are open, one short line telling the
  agent to record an answer if your prompt provides one. No nudge for decisions.
- The `statusline` plugin shows `🛑 N` (questions) and a dim `✎ N` (decisions),
  `notify-on-stop` sends an "Input needed" notification when questions are open,
  and `session-end` reviews pending decisions.

## State

`${XDG_STATE_HOME:-~/.local/state}/claude-inbox/<session_id>.json`. State is per
session: `/clear` starts fresh, and decisions do not survive it either.

## Skills

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `/inbox:show` | user-only | Read-only view of everything open |
| `/inbox:questions` | user-only | Read-only view of parked questions |
| `/inbox:decisions` | user-only | Read-only view of recorded decisions |
| `/inbox:respond` | user-only | Answer questions, then offer to confirm decisions |
| `/inbox:answer` | user-only | Walk through questions in chat, merge duplicates, record answers |
| `/inbox:confirm` | user-only | Walk through decisions: accept, change, or defer |
| `park-question` | model-only | When and how to park a blocking question |
| `record-decision` | model-only | When and how to record a decision made on a default |

## Tracker CLI

```text
inbox --session <id> add question --title T [--context C] [--option O]... [--recommend R] [--new]
inbox --session <id> add decision --title T [--context C] [--option O]... [--chosen X] [--new]
inbox --session <id> update <Q<n>|D<n>> [--title T] [--context C] [--option O]... [--recommend R] [--chosen X]
inbox --session <id> answer Q<n>
inbox --session <id> resolve D<n>
inbox --session <id> list [--kind question|decision] [--full] [--json]
inbox --session <id> count [--kind question|decision]
inbox prune [--days N]
```

`add` exits 3 when the title is similar to an open item of the same kind; use
`update` or pass `--new`.
