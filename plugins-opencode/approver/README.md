# approver (OpenCode)

A model-gated permission reviewer. OpenCode V2's base policy allows every
tool call that no rule asks about; this plugin sits in
`ctx.permission.hook("evaluate")` and lets a cheap model judge each remaining
action in light of what the user just asked for. The model either lets the
action through or escalates it to a real human prompt. It is OpenCode-only:
there is no Claude Code counterpart.

## Shape

- Server plugin only (`src/index.ts`), no skills, commands, or scripts.
- `src/approver-core.ts` holds the pure logic (options, pre-filter, prompt
  layering, decision, log entry). It is unit-tested.
- `src/hook.ts` is the only file that touches the permission hook, so moving
  to `experimental.review` (anomalyco/opencode#61824) is a single-file change.

## How an action is decided

1. A configured `deny` rule is final and never reaches the plugin.
2. **Pre-filter** (no model call). Shell actions carry one resource per
   scanned subcommand, so a compound command yields several.
   - any resource matches `ask` → escalate to a human;
   - every resource matches `allow` → leave the decision alone;
   - otherwise continue.
3. A rule-level `ask` is left for the human unless `overrideAsk` is set.
4. A **subagent** session's actions escalate (its prompt is model-written, so
   it is not user authorization) unless `subagents` is `"judge"`.
5. **Judge.** The policy prompt, the action and all its resources, and the
   latest user message are sent to the model as one `predicate` question
   (`approve`). `probability >= threshold` lets it through; anything else
   escalates with the configured message.
6. **Failure.** An error or timeout escalates (`onError: "ask"`, the default)
   or allows (`"allow"`).

By default the plugin only ever makes a decision stricter. Hard guarantees
(releases, force-push) belong in the `ask` list or a static rule, never in
the model's judgement.

## Install

Copy `opencode.jsonc` into your global `~/.config/opencode/opencode.jsonc` or a
project `opencode.jsonc`, fixing the path.

### No checkout? Install from GitHub

```sh
opencode plugin add 'github:St0nefish/agent-toolkit#master::path:plugins-opencode/approver'
```

```jsonc
{
  "plugins": [
    {
      "package": "github:St0nefish/agent-toolkit#master::path:plugins-opencode/approver",
      "options": { "model": "haiku", "shadow": true }
    }
  ]
}
```

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `model` | `haiku` | Tier name or literal `providerID/modelID` |
| `modelTiers` | `{}` | Tier → `providerID/modelID`; unset tiers fuzzy-match the enabled model list (same convention as the `session` plugin) |
| `prompt` | built-in | Inline policy text or a path to a markdown file |
| `allow` / `ask` | `[]` | Regex lists, matched against each resource and against `action:resource` |
| `threshold` | `0.5` | Minimum `approve` probability |
| `onError` | `ask` | `ask` or `allow` on judge error or timeout |
| `timeoutMs` | `4000` | Judge budget |
| `messageChars` / `messageWindow` | `2000` / `1` | Size cap per user message, and how many recent user messages to include (clamped to 1–10) |
| `subagents` | `escalate` | `escalate` or `judge` |
| `overrideAsk` | `false` | Let the model approve an action a rule marked `ask` |
| `headless` | `prompt` | When no client can answer a prompt (headless, `--auto`, `--yolo`): `deny` turns every escalation into a deny; `allow` turns model, error and subagent escalations into allows but never loosens the `ask` list or a rule-level `ask` |
| `askMessage` | built-in | Text shown on escalation |
| `shadow` | `false` | Log only; change no decision |
| `log` | `~/.local/state/agent-toolkit/approver.jsonl` | JSONL audit log |

### Prompt precedence

`.opencode/approver.md` in the project, then `options.prompt` (OpenCode
merges project config over user config), then
`~/.config/opencode/approver/prompt.md`, then the built-in default.

## Audit log

One JSON line per evaluated action: `ts`, `sessionID`, `agent`, `action`,
`resources`, `source` (`prefilter-allow`, `prefilter-ask`, `rule-deny`,
`rule-ask`, `subagent`, `model`, `error`), `verdict`, `reason`, `model`, `latencyMs`, `shadow`,
`promptSource`. Shadow mode writes the same lines enforcing mode would, with
the verdict the plugin would have applied.

## Notes

- A project's `.opencode/approver.md` replaces the user-level prompt, so
  an untrusted checkout can ship a permissive policy. Put anything that must
  hold regardless of project in the `ask` list or a static rule.
- The whole judged path (session lookups and the model call) shares one
  `timeoutMs` deadline. Resources are passed to the judge JSON-quoted and
  labelled untrusted so command text cannot forge a user message.
- The plugin has no way to detect a headless session on its own; set
  `headless` explicitly for those configs.
- The judge sees no tools or history beyond the bounded user messages, so a
  vague "yes" with no referent will usually escalate. That is intended.
- Choosing "always allow" in the TUI adds a rule; a rule-level allow still
  passes through this hook, but repeated "always allow" clicks on model
  escalations can shrink the escalation path over a session.
- `gh pr create` and similar are left to the model by default; put them in
  `ask` if a human must always confirm.
