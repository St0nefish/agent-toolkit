# Session

Work session management: two lightweight doors into a shared explore → plan spine,
a heavyweight multi-agent orchestrator, and a review-gated PR finalizer.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/session
```

## How It Works

Every entry point follows the same **begin-work spine** — *isolate (worktree) →
offer orchestration → explore (parallel research agents) → plan (plan mode) →
hand-off* — and they differ only in **how the work is chosen**:

- **`/session:session-start`** — the *input-driven* door. You describe what to do; it
  grounds in the current branch state, creates or reuses a branch, and runs the spine.
  If your description references an issue (`#42`), it links it.
- **`/session:session-issue`** — the *discovery* door. It ranks the open issues, asks
  you to pick from the top 3, then runs the same spine.

For non-trivial work, both doors offer to escalate to
**`/session:session-orchestrate`** — the multi-agent playbook (spec → plan → refine →
divide → execute → review) with model tiering and an automated review pass. The
lightweight spine is the single-session counterpart to this heavyweight flow.

The shared spine lives in [`reference/spine.md`](reference/spine.md); `start` and
`issue` read and execute it so there is one source of truth.

When an issue is linked, the branch name uses the issue's type and a slug
(`type-slug`, e.g. `bug-fix-login-crash`). The issue is auto-closed via `Closes #N`
in the PR when it merges — the linkage lives there, not in the branch name.

### Working Without Issues

`/session:session-start` accepts freeform descriptions and creates `wip-<slug>`
branches — no issue tracker required. The `/session:session-end` PR workflow works the
same either way.

## Commands

| Command | Description |
|---------|-------------|
| `/session:session-start` | Start from your description — ground, branch, explore, plan |
| `/session:session-issue` | Rank open issues, pick one, then explore and plan |
| `/session:session-orchestrate` | Multi-agent feature workflow: spec → plan → refine → divide → execute → review |
| `/session:session-end` | Review changes, open a PR, watch CI, wait for merge, return to default (worktree-aware) |

## Skills (Model-Triggered)

| Skill | Triggers on |
|-------|-------------|
| `summarize` | "what was I working on?", "session status", "catch me up", or returning to active work |

## Finalizing: `session-end` vs `git-tools:ship`

Both take in-flight work through commit → push → PR → CI → merge → return-to-default.
Pick based on what you need:

- **`/session:session-end`** — adds a pre-PR code-review gate and `Resolves #N`
  issue linking. Worktree-aware (tears down the worktree after merge).
- **`/git-tools:ship`** — the quick canonical lifecycle, no review gate. Also
  worktree-aware: after merge it returns to the main worktree, removes the merged
  worktree, prunes, and deletes the branch.

## Typical Workflow

```text
/session:session-start "add CSV export"   # or /session:session-issue to pick one
  → isolates in a worktree, explores, enters plan mode
  ... implement ...
/session:session-end                        # review, PR, watch CI, merge, tear down worktree
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
| `jq` | Yes | JSON processing in git-cli |

*Either `gh` or `tea` is required depending on your git remote host.

The `git-cli` wrapper is bundled as a vendored script in `scripts/` — you don't need
to install it separately, but you do need the underlying CLI tools.
