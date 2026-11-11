# plugins-opencode

OpenCode V2 ports of four agent-toolkit plugins. This tree is a **pure
addition**: nothing here changes Claude Code or Copilot behavior, and the
Claude/Copilot plugins are not loaded from here.

The intent, same as the Claude versions: the agent keeps working without
bugging you, while recording blockers, decisions, and followups for review
later. Where OpenCode has a better native mechanism (TUI slots instead of
`Stop`-hook banners, `question` tool instead of prompt re-injection), the
OpenCode port uses it.

## Plugins

| Plugin | Shape | Install |
| --- | --- | --- |
| `format-on-save` | config snippet only (no code) | copy `formatter` block into your config |
| `git-tools` | skills + commands config snippet (no code) | copy `skills` + `commands` entries |
| `inbox` | server plugin + TUI plugin + shared CLI | `opencode plugin add` (see below) |
| `session` | server plugin + skills + commands | `opencode plugin add` (see below) |

Shared scripts (`git-wait`, `branch`, `sitrep`, `inbox`) are vendored from
`../utils/` by `utils/sync.sh` — edit the canonical copy there and re-run
sync; CI fails on drift for this tree exactly like it does for
`plugins-claude/`.

## Install

Config snippets (`format-on-save`, `git-tools`): copy the `opencode.jsonc`
block from the plugin's README into your global `~/.config/opencode/opencode.jsonc`
or a project `opencode.jsonc`.

Code plugins (`inbox`, `session`) install from this repo's subdirectory:

```sh
opencode plugin add 'github:St0nefish/agent-toolkit#master::path:plugins-opencode/inbox'
opencode plugin add 'github:St0nefish/agent-toolkit#master::path:plugins-opencode/session'
```

Local paths work too (`plugins` array in `opencode.jsonc`, or a directory
under `.opencode/plugins/`), which is what you want while developing.

## State sharing

`inbox` keeps its state in `${INBOX_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/claude-inbox}`
— the same directory the Claude plugin uses. Session IDs differ per harness,
so the two can share the directory with no collision, and the `utils/inbox`
CLI is the single source of truth for both.
