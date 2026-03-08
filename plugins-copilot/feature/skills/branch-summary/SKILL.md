---
name: feature-branch-summary
description: >-
  Summarize branch changes versus main/master using a single context-optimized
  script output and return paragraph + categorized file/detail bullets.
allowed-tools: Task, Bash, Read
---

# Branch Summary

Use one script call as the source of truth, then summarize with an agent.

## Steps

1. Run:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/branch-summary
   ```

2. If output says `is_git_repo: false`, report that a branch summary cannot be generated outside a git repository.

3. Otherwise, invoke the Task tool (`agent_type: general-purpose`) and provide only this script output as input context.

4. Return exactly this structure:

   ```text
   <paragraph summarizing changes>

   * <major change category one summary>
     * <file 1>
       * <file 1 detail 1>
       * <file 1 detail 2>
     * <file 2>
       * <file 2 detail 1>
       * <file 2 detail 2>
   * <major change category two summary>
     * <file 3>
       * <file 3 detail 1>
   ```

## Rules

- Trust script sections as authoritative (do not run extra git commands unless script fails).
- Include committed + staged + unstaged + untracked file changes when present.
- Group files under 2-5 major categories (examples: "New functionality", "Refactors", "Fixes", "Docs/metadata").
- If `none_detected: true`, return only a short paragraph and no bullet list.
