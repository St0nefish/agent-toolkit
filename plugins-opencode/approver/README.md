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
5. **Judge.** One model call (`judgeMode: "text"` by default) sees, in order:
   your policy prompt, a fixed decision procedure the plugin adds (never-list
   first, then "the user explicitly named this action", then read-only or
   in-scope, else escalate), the action and all its resources marked untrusted,
   and last the latest user message as the only source of authorization. The
   model replies with a JSON verdict (`reason` first, then `approve`).
   `approve: true` lets it through; anything else, or an unparseable reply,
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
| `model` variants | none | Append `#variant` to a model (`provider/model#variant`, or a tier such as `haiku#nothink`). The variant is defined on the model in your provider config (its `body`/`settings` can, for example, turn thinking off) and is passed to `generate.text`; it is shown in the log's `model` field. Whether a given backend honors the setting is up to that backend: test it with `shadow: true` |
| `modelTiers` | `{}` | Tier → `providerID/modelID`; unset tiers fuzzy-match the enabled model list (same convention as the `session` plugin) |
| `prompt` | built-in | Inline policy text or a path to a markdown file |
| `allow` / `ask` | `[]` | Regex lists, matched against each resource and against `action:resource` |
| `threshold` | `0.5` | Minimum `approve` probability |
| `onError` | `ask` | `ask` or `allow` on judge error or timeout |
| `timeoutMs` | `4000` | Judge budget |
| `judgeMode` | `text` | `text` asks any chat model for a JSON verdict via `generate.text` (the default, works with self-hosted models). `decisions` uses `generate.decisions` and `threshold`, but OpenCode only allows it for models from provider packages that ship a decisions adapter (baseten, cloudflare, digitalocean, openrouter, vercel and similar; there is none for `openai-compatible`), and rejects chat models with "is a chat model, not a decision model" |
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
- **`--auto` / `--yolo` bypass escalation.** Tested on OpenCode 2.2.7: with
  `opencode run --auto`, a command the approver escalated (an `ask`-list hit)
  ran anyway, because the flag auto-approves everything that is not an explicit
  deny. Without `--auto`, a non-interactive `opencode run` rejects an escalation
  ("cannot ask the user for permission"), which is the safe outcome. If you run
  with `--auto`, put anything that must never run behind a `deny` rule (or set
  `headless: "deny"`, which turns escalations into denies; it applies to every
  session using that config, interactive ones included).
- Thinking-off judge models are much faster on this task: against a
  `qwen3.8-27b` endpoint the judge went from a ~20s p95 to ~1s with a
  `chat_template_kwargs.enable_thinking: false` variant, with the same
  agreement on the eval cases. Whether a backend honors such a setting is
  backend-specific; measure it with `approver-eval`.

## Developing and testing

Two project-local tools, both listed in the repo's `.claude/settings.json`
allow list so an agent can drive them without a permission prompt each time:

- `scripts/approver-eval` replays `eval/cases.json` through the plugin's real
  decision code (pre-filter, subagent rule, prompt layering, judge input,
  verdict parsing) and reports agreement with the expected verdicts. It calls
  the OpenAI-compatible endpoint from your OpenCode config directly, so it needs
  no session and runs in seconds. Useful flags: `--model` (including
  `#variant`), `--samples N --temperature T` (shows flakiness), `--only`,
  `--prompt-file` (A/B a policy), `--json`. Add a case whenever the approver
  gets a decision wrong.
- `scripts/approver-sandbox` drives live, free-form OpenCode sessions in a
  throwaway repo under a randomized temp directory (never a fixed path):
  `create`, `run <sandbox> --prompt …` (or `--session`/`--continue` to post to
  an existing session), `status`, `log` (the approver's decisions for a run,
  filtered by session id), `output` (the agent's tool calls and text),
  `sessions`, `export`, `list`, `destroy`. It uses a private server and archived
  sessions, so your running OpenCode is untouched. It reads your real OpenCode
  config and prints whether the approver is in shadow or enforcing mode before
  each run.
- The judge sees no tools or history beyond the bounded user messages, so a
  vague "yes" with no referent will usually escalate. That is intended.
- Choosing "always allow" in the TUI adds a rule; a rule-level allow still
  passes through this hook, but repeated "always allow" clicks on model
  escalations can shrink the escalation path over a session.
- `gh pr create` and similar are left to the model by default; put them in
  `ask` if a human must always confirm.
