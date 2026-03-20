# Session History Analyzer

Analyze Claude Code session history for workflow patterns, friction hotspots, and automation candidates.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/session-history-analyzer
```

## Commands

| Command | Description |
|---------|-------------|
| `/session-history-analyzer:analyze` | Full analysis — parse session logs, identify patterns, recommend automations |
| `/session-history-analyzer:status` | Show analyzed vs pending session counts per project |

Options for `analyze`: `--since <date>`, `--project <name>`, `--force` (re-analyze already processed sessions).

## How It Works

Reads Claude Code's JSONL session logs under `~/.claude/projects/` and extracts:

- Timestamps and duration
- Tool usage frequency
- Turn and compaction counts
- Friction indicators (hook blocks, repeated prompts)
- Workflow signals (agent use, web access, MCP usage)

Dispatches parallel analysis agents per project, then synthesizes a cross-project report with ranked recommendations.

Analysis state is persisted in `~/.claude/session-analysis/state.json` so sessions are only processed once (unless `--force`).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Session log location |
| `CLAUDE_STATE_DIR` | `~/.claude/session-analysis` | Analysis state and reports |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | JSONL parsing |
| `bash` | Yes | Script execution |
