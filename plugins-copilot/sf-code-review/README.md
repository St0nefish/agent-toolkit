# sf-code-review

Chunked cross-family code review for GitHub Copilot CLI — dual mid-range review with targeted high-end adjudication and triage-ready output.

> **Copilot CLI only.** This workflow depends on mixing model families inside one review pipeline.

## Installation

Install from the Copilot CLI plugin marketplace:

```text
sf-code-review plugin from St0nefish/agent-toolkit
```

## Slash command

```text
/sf-code-review:review [--base <ref>] [--staged] [--scope <path> ...] [--focus "<item>; <item>"] [--exception "<false-positive class>; <false-positive class>"]
```

Examples:

```text
/sf-code-review:review --focus "pega model as source of truth; syncDown source-set rollback"
/sf-code-review:review --base origin/master --focus "backward compatibility; migration safety"
/sf-code-review:review --staged --scope services/model services/sync --focus "config only via pega"
```

## How it works

1. Scopes the review from the staged diff, an explicit base ref, or the current branch against the default branch merge-base.
2. Collects review-specific focus items plus named false-positive exceptions.
3. Builds coherent chunks by semantic unit first, then diff size.
4. Runs a diff-wide cross-cutting sweep for architectural and integration risks.
5. Dual-reviews each chunk with **Claude Sonnet 4.6** and **GPT-5.4**.
6. Uses **Claude Opus 4.6** only to adjudicate candidate findings and disagreements — not to redo the whole review.
7. Consolidates a triage-ready report with confirmed issues, cross-cutting concerns, open questions, and rejected findings.

## Model roles

| Model | Role |
|---|---|
| `claude-sonnet-4.6` | First-pass chunk reviewer |
| `gpt-5.4` | First-pass chunk reviewer + default whole-diff cross-cutting sweep |
| `claude-opus-4.6` | Targeted adjudicator for candidate findings only |

## Review contract

- Custom focus items **add to** baseline review; they do not replace correctness, regression, compatibility, or test-gap checks.
- Exceptions only suppress named false-positive classes or intentional deviations; they do not waive real correctness, auth, security, or data-loss risks.
- Opus is an adjudicator, not a third full reviewer.
- Opus must be **exactly** `claude-opus-4.6`; do not substitute `claude-opus-4.7` or `claude-opus-4.8`.

## Output

The review report is organized for human triage:

1. Review metadata — base, scope mode, focus items, exceptions, chunk count
2. Confirmed issues — severity, confidence, file:line, reviewers, impact, recommended fix
3. Open questions / uncertain items
4. Cross-cutting concerns
5. Rejected findings
6. Counts and overall merge risk
