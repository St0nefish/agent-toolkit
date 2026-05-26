---
name: set
description: "Set a custom session-title suffix (auto-prefixed with the project name on the next user prompt)"
disable-model-invocation: true
allowed-tools: Bash
---

Write a per-worktree override so the next user prompt produces a session title of `<repo>:<custom-name>` instead of `<repo>:<branch>`.

### Steps

1. Extract the custom name from the user's invocation arguments. If no arguments were provided, print this and stop:

   ```text
   Usage: /auto-session-title:set <name>
   ```

2. Write the name to the per-worktree override file:

   ```bash
   GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || { echo "Not in a git repo"; exit 1; }
   printf '%s\n' "<name>" > "$GIT_DIR/claude-session-title"
   ```

3. Confirm in one line: the override is set and the title will become `<repo>:<name>` on the next user prompt.
