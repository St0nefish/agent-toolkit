---
description: "Analyze Claude Code session history for workflow patterns, friction hotspots, and automation candidates"
argument-hint: "[--since <date>] [--project <name>] [--force]"
allowed-tools: Bash, Agent, Read, AskUserQuestion
---

# Analyze Session History

Analyze Claude Code session JSONL files to identify workflow patterns, friction hotspots, and automation candidates.

## Arguments

- `--since <date>` — only analyze sessions modified after this date (ISO 8601)
- `--project <name>` — only analyze sessions for projects matching this name
- `--force` — re-analyze previously analyzed sessions

## Steps

1. **Discover sessions** — run the discovery script to enumerate available sessions:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/discover-sessions.sh [--since <date>] [--project <name>]
   ```

2. **Filter already-analyzed** — for each discovered session, check incremental state (unless `--force`):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh is-analyzed <session_id>
   ```

   Skip sessions that return exit 0 (already analyzed).

3. **Present summary and confirm** — show the user:
   - Number of projects with pending sessions
   - Total pending session count
   - Estimated scope

   Use `AskUserQuestion` to confirm before dispatching analysis agents.

4. **Dispatch per-project agents** — group pending sessions by `project_slug`. For each project cluster, launch an Agent subagent that:
   - Calls `parse-session.sh` on each session in the cluster
   - Aggregates results into a project-level summary: total sessions, total turns, top tools, common workflows, friction indicators, notable patterns
   - Returns the summary as structured JSON

   Use parallel Agent calls for independent project clusters.

   Example agent prompt:
   > Parse these session files and return a JSON summary:
   > - Run: `bash <plugin_root>/scripts/parse-session.sh <jsonl_path>` for each file
   > - Aggregate: total sessions, total turns, tool frequency, friction counts, workflow patterns
   > - Return a single JSON object with the project summary

5. **Mark analyzed** — for each processed session:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh mark-analyzed <session_id> <project_slug> <started_at>
   ```

6. **Synthesize report** — combine all project summaries into a consolidated analysis:
   - Cross-project patterns (common tools, shared workflows)
   - Friction hotspots (hook blocks, compactions, long sessions)
   - Automation candidates (repetitive tool patterns, manual steps)
   - Recommendations ranked by impact

7. **Present report** — display the consolidated report to the user. Offer to save it:

   ```bash
   mkdir -p ~/.claude/session-analysis/reports
   ```

   Save to `~/.claude/session-analysis/reports/YYYY-MM-DD.md` if the user agrees.

## Rules

- Always confirm with the user before dispatching analysis agents (step 3)
- Use Agent subagents for parallelism — one per project cluster
- The model synthesizes insights; scripts only extract raw data
- Mark sessions as analyzed only after successful parsing
- Reports should be actionable — prioritize concrete automation recommendations
