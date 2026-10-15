---
description: "Browse open issues, pick one or more, and start work on them"
allowed-tools: Bash, AskUserQuestion
---

Take the discovery path: rank the open issues, pick one or several, then explore the code and
propose a concrete plan before implementing.

This command invokes the sibling `session-issue` skill. The flow:

1. **Fetch and rank issues** with native host tooling (`gh` on GitHub, `tea` on Gitea; detect with `git-wait platform`). Numbers passed as arguments skip ranking but are validated (must be open, not a pull request).
2. **Let the user choose** by issue count: 0 → suggest `/session:start`; 1 → start it; 2-4 → AskUserQuestion; 5 or more → print the full ranked list and have the user type the number(s).
3. **Fetch the selected issues** and keep their bodies + labels as context.
4. **Choose the branch type** from labels, isolate the work on a branch or worktree, and record `git config branch.<b>.session-issues`.
5. **Explore, then plan** — inspect the codebase and present a concrete implementation plan, with a `Scope:` line; approval authorizes the whole scope through merge. Land each unit before the last via `/git-tools:ship` without stopping; run the last unit through `/session:end`, which ships it and then confirms with the user before the entire session is called complete.
