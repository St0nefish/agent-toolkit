# Crush Hooks Configuration for agent-toolkit

Crush hooks are implemented in PR #2612 but not yet merged to main. Once merged, you can configure hooks in `crush.json`:

## Current State

- **Hooks are in PR #2612** - Not yet merged to main branch
- **Branch**: `hooks` - Contains the implementation
- **CLA required** - External contributions need CLA signed

## Configuration (Once Hooks Are Merged)

Add to `crush.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "bash /path/to/crush-hook.sh"
      }
    ]
  }
}
```

## Hook Script Environment Variables

Crush sets these environment variables for hook scripts:

- `CRUSH_EVENT` - Event name (e.g., "PreToolUse")
- `CRUSH_TOOL_NAME` - Tool being called (e.g., "Bash", "Edit")
- `CRUSH_TOOL_INPUT_COMMAND` - The command string (for Bash tool)
- `CRUSH_TOOL_INPUT_FILE_PATH` - File path (for Edit tool)
- `CRUSH_SESSION_ID` - Session ID
- `CRUSH_CWD` - Current working directory

## Hook Output Format

Output JSON with:
- `decision` - "allow", "deny", or "ask"
- `reason` - Optional explanation
- `context` - Optional context to add to response
- `updated_input` - Optional modified tool input

Example:
```json
{
  "decision": "deny",
  "reason": "agent-toolkit: blocked dangerous command"
}
```

## Testing the Hook

```bash
# Test with a command that should be asked
CRUSH_EVENT=PreToolUse \
CRUSH_TOOL_NAME=Bash \
CRUSH_TOOL_INPUT_COMMAND="ls -la | grep foo" \
CRUSH_CWD=/tmp \
bash /path/to/crush-hook.sh
```

Expected output: `{"decision":"ask","reason":"agent-toolkit: ask"}`

## Integration with agent-toolkit

The hook script (`crush-hook.sh`) calls the permission-manager classifier:

1. Receives Bash command from Crush
2. Runs `cmd-gate.sh` classification via shfmt AST parsing
3. Returns allow/ask/deny decision to Crush
4. Crush blocks/allows based on decision

## Future Work

Once hooks are merged to main:

1. Build Crush from `hooks` branch or wait for merge
2. Configure hooks in `crush.json`
3. Test with various commands
4. Integrate real `cmd-gate.sh` classifier