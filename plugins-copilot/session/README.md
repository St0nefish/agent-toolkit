# Session

Work session management: two lightweight doors into a shared explore → plan spine,
a heavyweight multi-agent orchestrator, and a wrap-up skill that reviews, sweeps issues, and ships.

## Installation

```bash
copilot plugin install St0nefish/agent-toolkit/session
```

**Prerequisite:** `/session:end` hands off to `/git-tools:ship`, so the `git-tools`
plugin from this marketplace must be installed.

## How It Works

Every entry point follows the same **begin-work spine** — *isolate (worktree) →
explore (parallel research agents) → plan (plan mode) →
hand-off* — and they differ only in **how the work is chosen**:

- **`/session:start`** — the *input-driven* door. You describe what to do; it
  grounds in the current branch state, creates or reuses a branch, and runs the spine.
  If your description references an issue (`#42`), it links it; otherwise it
  searches open issues for related ones and offers to link any it finds.
- **`/session:issue`** — the *discovery* door. It ranks **all** open issues
  (issues labeled `deferred` always sort last), then picks by count: 0 → suggests `/session:start`; 1 → asks you to confirm; 2-4 → a
  multi-select picker; 5 or more → the full ranked list in text, and you type the
  number(s). You can also pass numbers up front (`#127 #125`); each is validated
  (must be open, not a pull request). Several issues share one branch/worktree and
  one plan.

Both doors always use the lightweight flow. The heavier playbook,
**`/session:orchestrate`** (spec → plan → refine → divide → execute → review), is
mentioned only if you ask for it. On Copilot it runs as a single-session workflow;
the Claude version adds multi-agent dispatch and model tiering.

The shared spine lives in the Claude-side `reference/spine.md`; `start` and
`issue` read and execute that same flow so there is one source of truth.

When an issue is linked, the branch name uses the issue's type and a slug
(`type-slug`, e.g. `bug-fix-login-crash`). The issue is auto-closed via `Closes #N`
in the PR when it merges — the linkage lives there, not in the branch name. The
closing lines are also persisted as `git config branch.<branch>.session-issues`
(comma-separated, e.g. `Closes #12,Fixes #13`), which the hand-off, `/session:end`,
and `/session:orchestrate` read back.

When you are already on a feature branch with commits or uncommitted work, the
doors continue it instead of creating a new one. If the target branch or worktree
already exists, they offer to resume it or use a numeric suffix.

### Working Without Issues

`/session:start` accepts freeform descriptions and creates `wip-<slug>`
branches — no issue tracker required. The `/session:end` PR workflow works the
same either way.

## Commands

| Command | Description |
|---------|-------------|
| `/session:start` | Start from your description — ground, branch, explore, plan |
| `/session:issue` | Rank open issues, pick one, then explore and plan |
| `/session:orchestrate` | Multi-agent feature workflow: spec → plan → refine → divide → execute → review |
| `/session:end` | Update docs, finish adjacent work, review + fix (hard gate, skipped only if already reviewed this session), sweep issues, then hand off to `/git-tools:ship` |

## Skills (Model-Triggered)

| Skill | Triggers on |
|-------|-------------|
| `summarize` | "what was I working on?", "session status", "catch me up", or returning to active work. Always reports committed context (unpushed and branch commits) alongside working-tree changes; broader repo activity only when everything is clean |

`skills/` holds **intentional copies** of the Claude-side skills (`session-issue`,
`session-summarize`), not symlinks — they diverge on purpose (no plugin-root
variable, no sub-agents). Keep them in sync by hand when the Claude versions change.

## Orchestrate State

`/session:orchestrate` persists its spec, plan, and chunk plan under the git dir
(`$(git rev-parse --git-path session-orchestrate)`: `spec.md`, `plan.md`,
`chunks.json`), so a later session can resume from Plan, Divide, or Execute. Branch
names and commit messages are not treated as evidence of prior work.

## Tests

Script tests live in `tests/session/` at the repo root (`test-branch.sh`,
`test-rename-session.sh`, `test-sitrep.sh`, and the PR/CI wait suites); run them all
with `bash test.sh`.

## Finalizing: `session-end` vs `git-tools:ship`

Both take in-flight work through commit → push → PR → CI → merge → return-to-default.
Pick based on what you need:

- **`/session:end`** — a thin wrapper around `/git-tools:ship`. It updates docs,
  finishes adjacent work, and enforces a code-review gate (`/sf-code-review:review`
  or a review agent, then fix) before shipping — skipped only if a review already
  ran this session on the current state. It also sweeps issues so `Closes #N` /
  `Fixes #N` lines reach the PR. Ship does the rest, including worktree teardown.
- **`/git-tools:ship`** — the quick canonical lifecycle, no review gate or docs pass. Also
  worktree-aware: after merge it returns to the main worktree, removes the merged
  worktree, prunes, and deletes the branch.

## Typical Workflow

```text
/session:start "add CSV export"   # or /session:issue to pick one
  → isolates in a worktree, explores, proposes a plan
  ... implement (left uncommitted; the agent stops and hands off with the
      branch state and closing lines - it never commits, pushes, or opens a PR) ...
/session:end                        # docs, review gate, close issues, ship
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
