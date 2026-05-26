---
description: "Analyze Copilot CLI session history for workflow patterns, friction hotspots, and automation candidates"
argument-hint: "[--since <date>] [--project <name>]"
allowed-tools: SQL, Task, AskUserQuestion
---

# Analyze Session History

Analyze Copilot CLI session history from the built-in session store to identify workflow patterns, friction hotspots, and automation candidates.

## Arguments

- `--since <date>` — only analyze sessions modified after this date (ISO 8601)
- `--project <name>` — only analyze sessions for repositories or working directories matching this name

## Steps

1. **Scope the history** — query `session_store` to enumerate matching sessions, turns, checkpoints, and edited files using the supplied filters.

2. **Present summary and confirm** — show the user:
   - number of matching projects
   - total matching session count
   - rough depth (turns, checkpoints, edited files)

   Use `AskUserQuestion` to confirm before dispatching analysis agents.

3. **Group by project** — cluster matching sessions by repository when available, otherwise by cwd.

4. **Dispatch per-project agents** — for each project cluster, launch a Task subagent that receives the relevant session-store rows and returns a structured summary:
   - total sessions
   - total turns
   - top tools and recurring workflows
   - friction indicators
   - notable patterns and recommendations

   Use parallel Task calls for independent project clusters when the scope is large enough to justify it.

5. **Synthesize report** — combine all project summaries into a consolidated analysis:
   - cross-project patterns
   - friction hotspots
   - automation candidates
   - recommendations ranked by impact

6. **Present report** — display the consolidated report to the user. Offer to save it to a markdown file if they want a persistent copy.

## Rules

- Always confirm with the user before dispatching analysis agents.
- Prefer the built-in `session_store` over plugin-private JSONL parsing when running inside Copilot CLI.
- Keep recommendations concrete and actionable.
