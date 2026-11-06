# inbox

A per-session inbox with three kinds of item, so "input needed" is a
deterministic flag derived from state rather than something the agent has to
remember to write.

- **Question** (`Q<n>`): blocks on you. Drives the input-needed flag.
- **Decision** (`D<n>`): the agent already proceeded on a reasonable default (a
  key choice you may want a say in). You review it later. Decisions never drive
  the flag.
- **Followup** (`F<n>`): work to consider before wrapping up that is not being
  done right now (out of scope, deferred, docs or tests not done, an issue worth
  filing). Close it with `done`. Followups are quiet like decisions and never
  drive the flag.

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
  - `🛑 INPUT NEEDED (N)` followed by the question cards (question, context, lettered options, recommendation): nothing else is running; the session is stuck on you.
  - `⏳ N parked question(s), still working`: background work is still running.
  - Nothing when no questions are open. Decisions and followups are quiet.
- **SessionStart hook**: gives the agent the exact tracker commands (with the
  session id) and the policy, re-injects open items after `/compact` or
  `/clear`, and prunes state files older than 7 days.
- **UserPromptSubmit hook**: while questions are open, one short line telling the
  agent to record an answer if your prompt provides one. No nudge for decisions.
- The `statusline` plugin shows `🛑 N` (questions), a dim `✎ N` (decisions) and a dim `☐ N` (followups),
  `notify-on-stop` sends an "Input needed" notification when questions are open,
  and `session-end` reviews pending decisions.

## State

`${XDG_STATE_HOME:-~/.local/state}/claude-inbox/<session_id>.json`. State is per
session: `/clear` starts fresh. Open items of all three kinds survive `/compact`, because the SessionStart hook re-injects them.

## Skills

| Skill | Invocation | Purpose |
|-------|------------|---------|
| `/inbox:show` | user-only | Read-only view of everything open |
| `/inbox:questions` | user-only | Read-only view of parked questions |
| `/inbox:decisions` | user-only | Read-only view of recorded decisions |
| `/inbox:followups` | user-only | Read-only checklist of logged followups plus a live sweep of loose ends (uncommitted or unpushed work, open PR or worktree, pending Q and D items) |
| `/inbox:respond` | user-only | Answer questions, then offer to confirm decisions |
| `/inbox:answer` | user-only | Walk through questions in chat, merge duplicates, record answers |
| `/inbox:confirm` | user-only | Confirm all open decisions (no args), or apply notes/exclusions |
| `/inbox:triage` | user-only | Interactive one-by-one pass (AskUserQuestion): answer questions, approve or change decisions |
| `park-question` | model-only | When and how to park a blocking question |
| `record-decision` | model-only | When and how to record a decision made on a default |
| `record-followup` | model-only | When and how to log work to consider before wrapping up |

## Tracker CLI

```text
inbox --session <id> add question --title T [--context C] [--option O]... [--recommend R] [--new]
inbox --session <id> add decision --title T [--context C] [--option O]... [--chosen X] [--new]
inbox --session <id> add followup --title T [--context C] [--new]
inbox --session <id> update <Q<n>|D<n>|F<n>> [--title T] [--context C] [--option O]... [--recommend R] [--chosen X]
inbox --session <id> answer Q<n>
inbox --session <id> resolve D<n>
inbox --session <id> done F<n>
inbox --session <id> list [--kind question|decision|followup] [--format line|text|md] [--full] [--json]
inbox --session <id> count [--kind question|decision|followup]
inbox prune [--days N]
```

`add` exits 3 when the title is similar to an open item of the same kind; use
`update` or pass `--new`.

## Output layout and writing convention

`list --format md|text` renders cards that put what you triage on first: the
**question** (title), then the **answer** (`chosen` for decisions, lettered
options plus the recommendation for questions). Alternatives sit on one
subordinate `instead:` line and a decision's context stays hidden; `--full`
shows one line per alternative and the full context. Plain `list` is still one
line per item and `--json` is unchanged.

To make that readable, agents write titles as questions ending in `?`, answers
as short phrases (about 80 characters, no reasons), options as short phrases,
and put reasoning in `--context`. `add` and `update` print a stderr hint (exit
code unchanged) when a title has no `?` or an answer or option exceeds 100
characters.
