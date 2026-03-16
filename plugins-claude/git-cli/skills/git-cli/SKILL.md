---
user-invocable: false
name: git-cli
description: >-
  This skill MUST be used for ALL GitHub and Gitea CLI operations. Never run
  `gh`, `tea`, `gh issue`, `gh pr`, `gh run`, `gh api`, `gh repo`, `tea issues`,
  or `tea pr` directly — always use git-cli instead. This skill should be used
  when the user asks to "list issues", "show issue", "file a bug", "create issue",
  "comment on issue", "list PRs", "show PR", "create PR", "merge PR", "check CI",
  "view run logs", "check build status", or any interaction with GitHub or Gitea
  issue trackers, pull requests, or CI systems. Provides a unified wrapper that
  auto-detects the platform from the git remote.
allowed-tools: Bash
---

# git-cli

**CRITICAL: Never run `gh` or `tea` directly.** Always use the wrapper script below.
The current repository may use GitHub or Gitea — the wrapper auto-detects the platform
from the git remote so the correct CLI is used every time. Running `gh` directly will
fail on Gitea repositories and vice versa.

```text
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli <command> <subcommand> [flags]
```

The interface mirrors `gh` syntax. Run `${CLAUDE_PLUGIN_ROOT}/scripts/git-cli --help`
for full usage. Commands: `issue`, `pr`, `run`, `repo`, `user` — each with subcommands
like `list`, `show`, `create`, `comment`, `close`, `merge`, `logs`.

All output is normalized JSON regardless of platform. Use `--body-file /tmp/file.md`
for multi-line issue/PR bodies.
