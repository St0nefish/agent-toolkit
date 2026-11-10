# inbox (OpenCode)

The OpenCode port of the inbox tracker — and where the port gets *better* than
the original. Claude Code has no persistent per-session UI, so the Claude
version re-injects a "🛑 INPUT NEEDED" banner at `Stop` and a statusline mod.
OpenCode has real TUI slots, so state is **continuously visible** and triage is
**keyboard-driven with zero model tokens**.

## Shape

- **Server plugin** (`src/index.ts`): registers the `agent-toolkit.inbox` RPC
  (implemented over the vendored `scripts/inbox` CLI — the same state file and
  state machine every harness shares), watches the state dir and emits
  `changed` events, drops a one-time session instruction hint at
  `session.created` (replaces the Claude `SessionStart`/`UserPromptSubmit`
  hook loop), and registers the `inbox:questions|decisions|followups|show`
  commands.
- **TUI plugin** (`src/tui.tsx`): footer flag (`🛑 N · ✎ D · ☐ F`), sidebar
  block with the session's open questions, and an `/inbox` triage panel
  (↑/↓ move, `a` answer, `d` acknowledge, `r` refresh). Answering writes
  through the CLI and feeds the answer back into the session — as a synthetic
  message when you resume it, as an instruction entry otherwise.
- **Shared CLI** (`scripts/inbox`, vendored from `utils/inbox`): the single
  source of truth. The new optional `blocking` field on questions defaults to
  `false` and does not change what a "question" means for Claude consumers.

## Non-blocking by default

Recording a question never stops the agent: it parks the question, states its
assumption (as a decision if it matters), and keeps working. `--blocking` is
the rare genuine "I cannot proceed" stop. The footer/sidebar show everything
passively; only **pings** fire on real stop signals: a `blocking` question
when a run ends, a `question`-tool form, or a permission request
(`attention.notify`, blurred-terminal aware).

## Install

```sh
opencode plugin add 'github:St0nefish/agent-toolkit#master::path:plugins-opencode/inbox'
```

or point a `plugins` entry at a local checkout. State lives in
`${INBOX_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/claude-inbox}` — shared
with the Claude plugin; session IDs differ per harness so there is no
collision.

## What did NOT port (deliberately)

- The `Stop`-hook banner, the prompt re-injection loop, the statusline mod —
  all replaced by continuous TUI visibility.
- `/inbox:triage` as a conversation — the panel does it with zero model tokens.
