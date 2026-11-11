# session (OpenCode)

The OpenCode port of the session workflow plugin: the five session skills
(start / issue / end / orchestrate / summarize), the shared spine reference,
and the headless build orchestrator that `session-orchestrate` dispatches.

## Shape

- **Server plugin** (`src/index.ts`): registers the `orchestrate_build` tool
  (the deterministic Execute-waves + Review/auto-fix half of
  `session-orchestrate`, ported from the Claude `Workflow` script) and the
  five slash doors (`/session-start` … — OpenCode skills take no slash
  arguments, so each door forwards its invocation text into the prompt).
- **`src/orchestrate-core.ts`**: the pure logic — tier bump, wave/dependency
  planning with transitive skip, output-block parsing (unparseable = retry,
  never a silent pass), 3-attempt failure escalation, findings dedupe/split.
  Unit-tested directly (`tests/opencode/test-session-core.sh`).
- **Skills** (`skills/*/SKILL.md`): ported from the Claude originals through
  `utils/opencode-port.py` — the same shared mapping `utils/sync.sh` uses for
  vendored markdown, so the port is single-sourced and re-runnable
  (`utils/port-session-skills.py`). `reference/spine.md` and the scripts
  (`git-wait`, `branch`, `sitrep`) are vendored per-skill by sync; CI fails
  on drift or on a stale port.

## Harness mapping (what changed vs Claude)

| Claude | OpenCode |
| --- | --- |
| `EnterWorktree` | `opencode.worktree_create` + `opencode.session_move` |
| `ExitWorktree` | `opencode.session_move` back / `opencode.worktree_remove` |
| `EnterPlanMode` | the built-in `plan` agent |
| `AskUserQuestion` | the `question` tool |
| `Agent` + `subagent_type` | the `subagent` tool + `agent` |
| `Workflow` script | the `orchestrate_build` tool (this plugin) |
| `rename-session` script | `opencode.session_rename` (Code Mode) |
| `/session:session-start` etc. | `/session-start` doors registered by the plugin |

`orchestrate_build` runs each chunk/review as its own top-level session
(create → prompt → wait → parse), not via the subagent tool — so the depth-1
subagent limit doesn't apply, and only the parent session ever has the tool
(no recursion).

## Install

Copy the `plugins` + `skills` entries from [`opencode.jsonc`](opencode.jsonc)
into your `~/.config/opencode/opencode.jsonc`, pointing both paths at your
checkout. Optional: pin model tiers via the plugin `options.modelTiers`
(see the commented block in the snippet); without it the plugin fuzzy-matches
your enabled model list for `haiku`/`sonnet`/`opus` and falls back to the
session default.

### No checkout? Install from GitHub

Both code plugins install straight from the public repo (OpenCode caches the
clone and checks unpinned refs for updates), and the skills come from the
generated HTTP catalog — no local checkout needed:

```jsonc
{
  "plugins": [
    "github:St0nefish/agent-toolkit#master::path:plugins-opencode/inbox",
    {
      "package": "github:St0nefish/agent-toolkit#master::path:plugins-opencode/session",
      "options": { "modelTiers": { "haiku": "…", "sonnet": "…", "opus": "…" } }
    }
  ],
  "skills": ["https://raw.githubusercontent.com/St0nefish/agent-toolkit/master/skills-catalog/"]
}
```

Pin `#master` to a tag or commit hash if you want a frozen revision.

## Notes

- The Claude `SessionStart` hook has no OpenCode equivalent and none is
  needed: the skills are the entry points, and the doors make them one
  keystroke away.
- `orchestrate_build` children edit the session's working tree directly (the
  Phase 0b worktree, if one was created) — same shared-tree model as the
  Claude workflow.
