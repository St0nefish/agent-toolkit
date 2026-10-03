# Session

Work session management: two lightweight doors into a shared explore → plan spine,
a heavyweight multi-agent orchestrator, and a wrap-up skill that reviews, sweeps issues, and ships.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/session
```

**Prerequisite:** `session-end` hands off to `git-tools:ship`, so the `git-tools`
plugin from this marketplace must be installed (declared in `plugin.json`
`dependencies`, so it installs automatically).

## How It Works

The two lightweight doors share one **begin-work spine** — *resolve target →
isolate (worktree by default) → explore (parallel research agents, skipped for
trivial changes) → plan (plan mode) → hand-off* — and differ only in **how the work
is chosen**:

- **`/session:session-start`** — the *input-driven* door. You describe what to do; it
  grounds in the current branch state (`git status --short -b`), creates or reuses a
  branch, and runs the spine. If your description references issues (`#42`), it
  links them.
- **`/session:session-issue`** — the *discovery* door. It ranks **all** open issues,
  then picks by count: 0 → suggests `session-start`; 1 → asks you to confirm;
  2-4 → a multi-select picker; 5 or more → the full ranked list in text, and you
  type the number(s). You can also pass numbers up front (`#127 #125`). Several
  issues share one branch/worktree and one plan.

Both doors always use the lightweight flow and decide worktree vs in-place and
dependency symlinks silently. The heavier multi-agent playbook,
**`/session:session-orchestrate`** (spec → plan → refine → divide → execute → review,
with model tiering and an automated review pass), runs only when you invoke it. It
has its own phases and does not follow the spine; `session-summarize` is a read-only
status view and does not either.

The shared spine lives in [`reference/spine.md`](reference/spine.md); `start` and
`issue` read and execute it so there is one source of truth.

### Branch names

When an issue is linked, the branch uses the issue's type and a slug
(`<type>-<slug>`, e.g. `bug-fix-login-crash`); freeform work uses `wip-<slug>`. In a
worktree (the default), `EnterWorktree` adds its prefix, so the actual branch is
`worktree-<type>-<slug>` (e.g. `worktree-bug-fix-login-crash`). Issues are
auto-closed via `Closes #N` / `Fixes #N` lines in the PR body — the linkage lives
there, not in the branch name.

### Working Without Issues

`/session:session-start` accepts freeform descriptions and creates `wip-<slug>`
branches — no issue tracker required. The `/session:session-end` wrap-up works the
same either way.

## Commands

| Command | Description |
|---------|-------------|
| `/session:session-start` | Start from your description — ground, branch, explore, plan |
| `/session:session-issue` | Rank open issues, pick one or more, then explore and plan |
| `/session:session-orchestrate` | Multi-agent feature workflow: spec → plan → refine → divide → execute → review |
| `/session:session-summarize` | Summarize the current repo state (also auto-triggers) |
| `/session:session-end` | Update docs, finish adjacent work, review + fix (hard gate, skipped only if already reviewed this session), sweep issues, then hand off to `/git-tools:ship` |

## Skills (Model-Triggered)

| Skill | Triggers on |
|-------|-------------|
| `session-summarize` | "what was I working on?", "session status", "catch me up", or returning to active work |

## Finalizing: `session-end` vs `git-tools:ship`

`session-end` is a thin wrapper around `git-tools:ship`. Before handing off it updates
docs, finishes adjacent work, runs a code review + fix pass (a hard gate: skipped only if a review already ran this
session on the current state of the work, never offered as a skip), and sweeps open issues so
resolved ones get `Closes #N` / `Fixes #N` in the PR. `ship` does the rest (commit, PR,
CI, merge, worktree teardown — step 9 of `ship`). Use `/git-tools:ship` directly when you want only the
lifecycle with no pre-flight.

## Typical Workflow

```text
/session:session-start "add CSV export"   # or /session:session-issue to pick one
  → isolates in a worktree (by default), explores, enters plan mode
  ... implement (left uncommitted) ...
/code-review high --fix                     # optional
/session:session-end                        # docs, review + fix, close issues, ship
```

## Branch Type Detection

When starting from an issue, the branch type is inferred from issue labels:

| Labels | Branch prefix |
|--------|--------------|
| `bug`, `fix` | `bug-` |
| `enhancement`, `feature`, `improvement` | `enhancement-` |
| `docs`, `chore`, `refactor`, `maintenance` | `chore-` |
| (none of the above) | `feature-` |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `git` | Yes | All branch, commit, and diff operations |
| `gh` | Yes* | GitHub API — issues, PRs, CI |
| `tea` | Yes* | Gitea API — issues, PRs, CI |
| `jq` | Yes | JSON processing for `gh`/`tea` output and `git-wait` |

*Either `gh` or `tea` is required depending on your git remote host.

Skills call `gh`/`tea` directly for issue and PR CRUD, listing, comments, merging,
and logs. `git-wait` is bundled as a vendored script in `scripts/` for the two
things neither CLI gives you: platform detection (`git-wait platform`) and blocking
waits for a PR to merge (`git-wait pr wait`) or CI to finish (`git-wait run watch`).
You don't need to install it separately, but you do need the underlying CLI tools.
