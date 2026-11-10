#!/usr/bin/env python3
"""opencode-port.py — render Claude-harness prose for the OpenCode harness.

Single source of truth for the harness mapping, used by:
  - utils/sync.sh, to render vendored markdown (spine.md) for the
    plugins-opencode target, and
  - the one-time skill port (tests/opencode/test-session-port.sh re-checks
    the ported skills against `sync.sh`-style rendering of the originals).

Ordered exact-string substitutions; longest/most specific first. Anything
not listed passes through unchanged — the port must be minimal and auditable.
The Claude target renders identity (sync.sh only calls this for opencode).
"""

import sys

SUBST = [
    # --- script paths: skill-relative (skill base dir is provided at load) ---
    (
        '**Rename the session** (always, last — `rename-session` keys off the current\ndirectory, which `EnterWorktree` changes). Use the session name from Phase 0 step 3:\n\n```bash\nbash ${CLAUDE_PLUGIN_ROOT}/scripts/rename-session "<session-name>"\n```',
        '**Rename the session** (always, last). Use the session name from Phase 0 step 3:\n\n```ts\n// Code Mode — no script, no ~/.claude writes\nawait tools.opencode.session_rename({ title: "<session-name>" })\n```',
    ),
    ("bash ${CLAUDE_PLUGIN_ROOT}/scripts/", "bash scripts/"),
    ("${CLAUDE_PLUGIN_ROOT}/scripts/", "scripts/"),
    ("${CLAUDE_PLUGIN_ROOT}/reference/", "reference/"),
    # --- worktrees: EnterWorktree → opencode.worktree_* + session_move -------
    # ExitWorktree entries first: one block below contains `EnterWorktree`,
    # which the generic mappings would rewrite before a later match could fire.
    (
        'call `ExitWorktree` with\n`action: "keep"` (see step 8), or switch to a valid directory such as the main\ncheckout.',
        "move this session out with `opencode.session_move` (see step 8), or switch to a valid directory such as the main\ncheckout.",
    ),
    (
        'If this session was entered with `EnterWorktree` and the worktree directory no\nlonger exists after `ship` (ship removes it with plain git), call `ExitWorktree`\nwith `action: "keep"` to reset the harness\'s session state (do this at the start\nof step 7 when that step has work to do). Never use `remove`\nor `discard` here; `ship` already removed the directory.',
        "If this session was moved into a worktree with `opencode.worktree_create` and that\ndirectory no longer exists after `ship` (ship removes it with plain git), call\n`opencode.session_move` back to the main checkout to reset the session's working\ndirectory (do this at the start of step 7 when that step has work to do). Do not\nre-create or delete anything here; `ship` already removed the directory.",
    ),
    ("leave with `ExitWorktree`.", "remove it later with `opencode.worktree_remove`."),
    (
        "or the user can leave it and exit later with `ExitWorktree`.",
        "or the user can remove it later with `opencode.worktree_remove`.",
    ),
    ("`ExitWorktree`", "`opencode.worktree_remove`"),
    ("ExitWorktree", "opencode.worktree_remove"),
    (
        "This creates branch `worktree-<base-name>`, runs\n   native provisioning, and switches the session into the worktree. Do **not** also\n   run `branch create`.",
        "This creates the worktree (with its own branch) and returns its\n   directory; then move this session into it with `opencode.session_move`\n   (Code Mode). Do **not** also run `branch create`.",
    ),
    ("`EnterWorktree` with `path`", "`opencode.session_move` with that `directory`"),
    (
        "call `EnterWorktree` with `name` set to the base",
        "call `opencode.worktree_create` with `name` set to the base",
    ),
    ("read at `EnterWorktree` time", "read at `worktree_create` time"),
    ("`EnterWorktree` (Phase 1)", "`opencode.worktree_create` (Phase 1)"),
    ("EnterWorktree", "opencode.worktree_create"),
    # --- plan mode: EnterPlanMode → the built-in plan agent -------------------
    (
        "until you have called `EnterPlanMode` with a plan",
        "until you have switched to the `plan` agent with a plan",
    ),
    ("short plan inside `EnterPlanMode`", "short plan inside the `plan` agent"),
    (
        "Call `EnterPlanMode`, then present",
        "Switch the session to the built-in `plan` agent, then present",
    ),
    ("`EnterPlanMode`", "the `plan` agent"),
    # --- subagents: Agent + subagent_type → subagent tool + agent -------------
    ("`Agent` with `subagent_type: research`", "`subagent` tool with `agent: explore`"),
    ("subagent_type: research", "agent: explore"),
    ("subagent_type", "agent"),
    # --- user gates: AskUserQuestion → the question tool -----------------------
    ("`AskUserQuestion`", "the `question` tool"),
    ("AskUserQuestion", "the `question` tool"),
    # --- orchestration: Claude Workflow primitive → session.orchestrate_build --
    # Order matters: the multi-line dispatch block must match the ORIGINAL
    # text, so it precedes the generic ${CLAUDE_PLUGIN_ROOT} rewrites would
    # have touched it — but those run earlier in this list, so match the
    # already-path-rewritten form here. Phrase forms, then catch-all.
    (
        "Call the `Workflow` tool with:\n   - `scriptPath: scripts/orchestrate-build.workflow.js`\n   - `args: <the object from step 2>` (pass it as an actual JSON value, not a stringified blob)",
        "Call the `orchestrate_build` tool with:\n   - `args: <the object from step 2>` (the same args contract the Claude workflow script took; pass it as an actual JSON value)",
    ),
    (
        "(`scripts/orchestrate-build.workflow.js`)",
        "(implemented by the `agent-toolkit.session` plugin)",
    ),
    ("`scripts/orchestrate-build.workflow.js`", "the `agent-toolkit.session` plugin"),
    ("`orchestrate-build.workflow.js`", "the `orchestrate_build` tool's schema"),
    ("`Workflow` call", "`orchestrate_build` tool call"),
    ("in a `Workflow`", "in the `orchestrate_build` tool"),
    ("`Workflow` tool", "`orchestrate_build` tool"),
    (
        "the build-and-verify `Workflow`",
        "the build-and-verify `orchestrate_build` tool",
    ),
    ("the `Workflow`", "the `orchestrate_build` tool"),
    ("The Workflow ", "orchestrate_build "),
    ("the Workflow ", "orchestrate_build "),
    ("a targeted Workflow", "a targeted orchestrate_build"),
    (
        "You can watch progress via `/workflows`.",
        "Progress arrives as each wave completes.",
    ),
    ("Workflow", "orchestrate_build"),
    # --- slash-command doors: /plugin:name → skill id / command -----------------
    ("/session:session-", "session-"),
    ("/git-tools:ship", "/ship"),
]


def render(text: str) -> str:
    for old, new in SUBST:
        text = text.replace(old, new)
    return text


if __name__ == "__main__":
    data = sys.stdin.read()
    sys.stdout.write(render(data))
