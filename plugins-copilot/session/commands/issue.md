---
description: "Browse open issues, pick one, and start work on it"
allowed-tools: Bash, AskUserQuestion
---

Take the discovery path: rank the open issues, pick one, then explore the code and
propose a concrete plan before implementing.

This command invokes the sibling `session-issue` skill. The flow:

1. **Fetch and rank issues** with native host tooling (`gh` on GitHub, host-native equivalent elsewhere).
2. **Let the user choose** from the top-ranked issues via AskUserQuestion.
3. **Fetch the selected issue** and keep its body + labels as context.
4. **Choose the branch type** from labels and isolate the work on a branch or worktree.
5. **Offer orchestration** for non-trivial issues via `/session:orchestrate`.
6. **Explore, then plan** — inspect the codebase and present a concrete implementation plan.
