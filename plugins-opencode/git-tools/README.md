# git-tools (OpenCode)

Skills + commands port of the Claude `git-tools` plugin. **No plugin code** —
`git-wait`, `branch`, and `sitrep` are platform-neutral bash over `gh`/`tea`/git
and run unchanged; they're vendored from `../../utils/` by `utils/sync.sh`
(CI fails on drift).

## What's here

- `skills/git-wait/` — the gh-vs-tea command map, platform detection, and the
  blocking `pr wait` / `run watch` waiters. `scripts/git-wait` is vendored
  inside the skill dir so the skill's relative paths resolve from its base dir.
- `skills/ship/` — the full merge-lifecycle orchestrator (stage → commit →
  push → PR → CI watch → merge wait → post-merge run watch → default branch →
  worktree cleanup). Same procedure as the Claude skill; `$ARGUMENTS` wording
  became "arguments provided with the invocation".
- `commands/ship.md` — the `/ship` slash-command door for the ship skill.

## Install

Copy the `skills` and `commands` entries from [`opencode.jsonc`](opencode.jsonc)
into your `~/.config/opencode/opencode.jsonc`, pointing the skills path at your
checkout of this repo:

```jsonc
{
  "skills": ["~/agent-toolkit/plugins-opencode/git-tools/skills"],
  "commands": { "ship": { … } }
}
```

(OpenCode also auto-discovers `~/.claude/skills` and `.agents/skills` — if you
symlink this `skills/` dir into one of those, the `skills` entry is unnecessary.)

## Notes

- The Claude skill's `allowed-tools: Bash` frontmatter has no OpenCode
  per-skill equivalent; these skills only run bash, which is allowed by
  default. Tighten with a `permissions[]` rule or a dedicated agent if you
  want a gate.
- `branch` and `sitrep` are vendored for the `session` plugin's skills; this
  plugin only ships `git-wait` (same as its Claude counterpart).
