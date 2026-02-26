# Copilot CLI Hook Compatibility: bash-safety `ask` → silent passthrough

## Problem

`bash-safety` classifies Bash commands into three buckets:
- `allow` — read-only git/gradle ops, auto-approved
- `ask` — write git/gradle ops, redirection, dangerous find; user prompted to confirm
- (implicit deny for truly destructive ops)

Claude Code supports `permissionDecision: "ask"` which triggers a user confirmation dialog.
Copilot CLI only supports `"deny"` — there is no `"ask"` equivalent.

Currently `hook-compat.sh` maps `ask` → `deny` for Copilot CLI, which hard-blocks all
write operations. This is too aggressive — the goal is to *prompt*, not *block*.

## Solution

For Copilot CLI, `ask` cases should **exit 0 with no output**. When a hook returns no
`permissionDecision`, Copilot CLI falls through to its native permission system, which
prompts the user for tool approval. This gives the same UX intent:

| Case | Claude Code | Copilot CLI |
|------|-------------|-------------|
| Read-only git/gradle | `allow` (fast-track) | `allow` (fast-track) |
| Write git/gradle | `ask` (hook prompt) | exit 0 (native prompt) |
| Shell redirection, find -delete | `ask` (hook prompt) | `deny` (hard block) |

## Implementation

Change `hook_ask()` in `utils/hook-compat.sh`:

```bash
hook_ask() {
  local reason="$1"
  if [[ "$HOOK_FORMAT" == "copilot" ]]; then
    # Copilot CLI has no "ask" — exit silently so native permission system prompts
    exit 0
  else
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  fi
}
```

Note: truly destructive ops (redirection, `find -delete`) should use `hook_deny` not
`hook_ask` for Copilot CLI — they should be hard-blocked regardless. Review `bash-safety.sh`
to split current `ask()` calls into appropriate buckets:
- Shell redirection → `deny` on both CLIs
- `find -delete` → `deny` on both CLIs  
- Write git/gradle → `ask` (Claude) / silent passthrough (Copilot)

## Files to Change

- `utils/hook-compat.sh` — update `hook_ask()` for Copilot silent exit; add `hook_deny()`
- `plugins/bash-safety/scripts/bash-safety.sh` — split `ask()` calls into `ask()` vs hard deny
- Reinstall `bash-safety` in both CLIs after changes
- Update tests to cover Copilot CLI input format for ask/deny cases

## Verified Facts (from index.js source)

- `permissionDecision: "deny"` → hard blocks with message "Denied by preToolUse hook: <reason>"
- `permissionDecision` absent → falls through to Copilot's native permission handling
- `modifiedArgs` → rewrites tool arguments (not needed here)
- `${CLAUDE_PLUGIN_ROOT}` is substituted in hook commands (same var as Claude Code)
- Payload: `{sessionId, timestamp, cwd, toolName, toolArgs}` (camelCase, toolArgs as string)
