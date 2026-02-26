---
name: session-catchup
description: >-
  Rebuild context on a branch you've been working on. Use when resuming work,
  switching back to a branch, or starting a new Claude session on in-progress
  work. Gathers branch state, changed files, and lists context files to read.
allowed-tools: Bash, Read
---

# Catch Up on Branch Context

Quickly rebuild understanding of in-progress work.

## Steps

1. Gather current state in one bash call:

   ```bash
   BASE=$(git rev-parse --verify main 2>/dev/null && echo main || git rev-parse --verify master 2>/dev/null && echo master || echo "")
   BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not a git repo")
   echo "=== BRANCH ==="
   echo "current: $BRANCH"
   if [ -n "$BASE" ] && [ "$BRANCH" != "$BASE" ]; then
     echo "base: $BASE"
     echo "ahead: $(git rev-list --count "$BASE..HEAD") commits"
     echo ""
     echo "=== BRANCH COMMITS ==="
     git log --oneline "$BASE..HEAD"
     CHANGED=$(git diff --name-only "$BASE..HEAD")
     if [ -n "$CHANGED" ]; then echo ""; echo "=== CHANGED FILES (vs $BASE) ==="; echo "$CHANGED"; fi
   else
     echo ""; echo "=== RECENT COMMITS ==="; git log --oneline -10
   fi
   git log -1 --format=%s | grep -q "^WIP:" && echo "" && echo "=== LATEST HANDOFF ===" && git log -1 --format=%B
   STAGED=$(git diff --name-only --cached); UNSTAGED=$(git diff --name-only); UNTRACKED=$(git ls-files --others --exclude-standard)
   if [ -n "$STAGED$UNSTAGED$UNTRACKED" ]; then
     echo ""; echo "=== UNCOMMITTED ==="
     [ -n "$STAGED" ] && echo "staged:" && echo "$STAGED"
     [ -n "$UNSTAGED" ] && echo "unstaged:" && echo "$UNSTAGED"
     [ -n "$UNTRACKED" ] && echo "untracked:" && echo "$UNTRACKED"
   fi
   [ -f .claude/todo.md ] && echo "" && echo "=== TODO ===" && cat .claude/todo.md
   PLANS=$(ls -t .claude/plans/*.md 2>/dev/null); [ -n "$PLANS" ] && echo "" && echo "=== PLANS ===" && echo "$PLANS"
   SESSIONS=$(ls -t .claude/sessions/*.md 2>/dev/null)
   if [ -n "$SESSIONS" ]; then
     echo ""; echo "=== SESSIONS ==="
     for f in $SESSIONS; do
       grep -q "Status.*active" "$f" 2>/dev/null && echo "$f  (active)" || echo "$f"
     done
   fi
   ```

   If a directory was provided, `cd` into it first.

2. After reviewing the output, use the Read tool selectively:
   - Plans — only read if resuming a specific planned effort
   - Most recent session file — for prior context and decisions
   - Do NOT re-read `.claude/todo.md` — already in the output above

3. Read changed files (committed + uncommitted). If more than 15, prioritize:
   - Source code over generated files
   - Files mentioned in commit messages
   - Test files alongside their implementations

4. Present a concise summary:
   - **Branch:** name and commits ahead
   - **What's been done:** from commits and session notes
   - **What's in progress:** uncommitted changes and open TODOs
   - **Key files:** most important changed files
   - **Suggested next steps:** from TODOs, session notes, or incomplete work

## Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to minimize token usage
