# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Reusable Claude Code plugins plus a small number of Copilot CLI extensions for development workflows. Plugins are distributed via the marketplace; user-level Copilot extension sources live in-repo under `copilot-extensions/`.

## Structure

```text
agent-toolkit/                              # marketplace repo
├── .claude/
│   └── agents/
│       ├── plugin-validator.md              # structural validator subagent
│       └── research.md                      # read-only research subagent
├── .claude-plugin/
│   └── marketplace.json                     # Claude Code marketplace catalog
├── .github/plugin/
│   └── marketplace.json                     # Copilot CLI marketplace catalog
├── copilot-extensions/
│   └── git-worktree/                        # Copilot CLI user-level extension source
├── plugins-claude/                          # canonical plugin sources
│   ├── agentic-ide/                         # skills + agent: Serena (LSP) + ast-grep + Semgrep
│   ├── convert-doc/                         # skill: pandoc document conversion
│   ├── elevated-edit/                       # skill: SSH/sudo pull-edit-push via rsync
│   ├── format-on-save/                      # hook: auto-format after Edit/Write
│   ├── git-tools/                           # skills: GitHub/Gitea CLI wrapper plus ship orchestrator
│   ├── image/                               # skills: clipboard paste + screenshot
│   ├── java-toolkit/                        # MCP + skills: Maven Central + class index + jar-explore (Docker Compose)
│   ├── kb-capture/                          # skills: research-to-document automation
│   ├── markdown/                            # skill: lint, format, setup
│   ├── meal-planning/                       # skills: recipe authoring + plan + cart + dinner lookup (KB-backed)
│   ├── notify-on-stop/                      # hook: desktop notification on completion
│   ├── permission-manager/                  # hook + skills: Bash safety classifier
│   ├── session/                             # skills: work session management
│   ├── session-history-analyzer/            # skills: analyze Claude session JSONL history
│   ├── statusline/                          # skill: configurable Claude Code status line
│   └── stl-game-config/                     # skills: SteamTinkerLaunch config (Linux gaming)
├── plugins-copilot/                         # Copilot CLI variants
│   ├── <plugin>/commands/                   # Copilot-only slash-command surface
│   ├── <plugin>/hooks/hooks.json            # Copilot-format hooks for hook plugins
│   └── <plugin>/<other-dirs> -> ../../plugins-claude/<plugin>/...  # symlinked back
├── scripts/
│   └── install-copilot-git-worktree.sh      # user-level install/update helper for the Copilot extension
└── utils/                                   # shared scripts (vendored into plugin scripts/)
    ├── sync.sh                              # vendoring manifest + copier (run after edits)
    ├── approve-own-scripts.sh               # PreToolUse: auto-approve own scripts
    ├── hook-compat.sh                       # hook payload normalizer
    ├── git-cli                              # GitHub/Gitea CLI wrapper
    ├── detect-schema.sh                     # frontmatter schema/taxonomy discovery
    └── validate-frontmatter.sh              # frontmatter validation against schema
```

Each plugin follows this internal layout:

```text
plugins-claude/<name>/
├── .claude-plugin/
│   └── plugin.json          # required: name, version, description
├── skills/                  # auto-discovered skill directories (slash + auto-trigger)
│   └── <skill-name>/
│       └── SKILL.md         # skill definition with YAML frontmatter
├── hooks/
│   └── hooks.json           # hook event configuration
├── mcp.json                 # MCP server definitions (declared in plugin.json)
└── scripts/                 # helper scripts (referenced via ${CLAUDE_PLUGIN_ROOT})
```

## Plugin Components

| Type | Location | Format | Discovery |
|------|----------|--------|-----------|
| Skills | `skills/<name>/SKILL.md` | Markdown with YAML frontmatter | Auto-discovered |
| Commands | `commands/<name>.md` | Markdown with YAML frontmatter | Copilot-only on this side; see below |
| Hooks | `hooks/hooks.json` | JSON with `{hooks: {Event: [...]}}` wrapper | Auto-registered |
| MCP servers | `mcp.json` | JSON with `{mcpServers: {...}}` | Declared in `plugin.json` via `mcpServers` field |
| Scripts | `scripts/<name>` | Bash/Python executables | Referenced from skills/hooks |

## Skill invocation flags

On the **Claude side** (`plugins-claude/`), every user-facing slash entry is a skill. Two frontmatter flags determine how the skill is invoked:

| Flag combination | Slash-invocable? | Model auto-triggers? |
|---|---|---|
| (default — neither flag set) | yes | yes |
| `disable-model-invocation: true` | yes | **no** — equivalent to a "user-only command" |
| `user-invocable: false` | **no** | yes — model-only background guide |
| both | invalid (skill becomes unreachable) | — |

**Convention for new skills:**

- *User-only workflow* (formerly a `/command`): set `disable-model-invocation: true`. The skill appears in `/` autocomplete; the model can't auto-invoke. Description bytes are not loaded into the model's context budget.
- *Model-helper background guide* (e.g., `serena-cheatsheet`, `git-cli`, `ast-grep`): set `user-invocable: false`. Model-only.
- *Both* (auto-trigger AND user-invocable, e.g., `session/summarize`): leave both flags off.

For non-plugin skills (personal `~/.claude/skills/` or project `.claude/skills/`), `disable-model-invocation: true` in frontmatter is equivalent to setting `skillOverrides[<name>] = "user-invocable-only"` in settings.json. **`skillOverrides` does not apply to plugin-sourced skills** — per [the docs](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings), those are managed via `/plugin` and there is no per-skill override knob. The only way to mark a plugin skill user-invocable-only is to set the flag in its `SKILL.md` frontmatter at the source. To reduce skill-listing budget pressure from plugin skills, raise [`skillListingBudgetFraction`](https://code.claude.com/docs/en/settings) instead.

## Why Claude has no `commands/` directory

The Claude side uses `skills/` exclusively. The `commands/` directory pattern only exists in `plugins-copilot/` because Copilot CLI doesn't reliably register skills with `user-invocable: true` as slash commands — a separate `commands/<name>.md` file is the workaround. On Claude side, `disable-model-invocation: true` in a skill achieves the same "user-only slash command" semantics without a separate file, so the redundancy was removed.

This means the two sides intentionally diverge: `plugins-copilot/<name>/commands/` is a real directory, while `plugins-claude/<name>/` has none. Symlinking commands across the two sides is no longer possible.

## Project Agents

Agents live at `.claude/agents/<name>.md` and are auto-discovered by Claude Code. They are project-level configuration, not plugin components — no `plugin.json` registration, no marketplace entry, and no Copilot mirroring needed.

| Agent | Purpose | Tools |
|-------|---------|-------|
| `plugin-validator` | Validate plugin structure, manifests, hooks | Read, Glob, Grep, Bash |
| `research` | Read-only research and investigation | Read, Glob, Grep, Bash, WebFetch, WebSearch |

Agents are invoked via the `Agent` tool with `subagent_type: <name>`. Use `research` for any investigation task that must not make changes to the repository.

## Shared Scripts

`utils/` is the canonical source for scripts used by more than one plugin (`approve-own-scripts.sh`, `hook-compat.sh`, `git-cli`, `detect-schema.sh`, `validate-frontmatter.sh`). Each consuming plugin carries a **real file copy** at `plugins-claude/<name>/scripts/<util>` — not a symlink.

### Why vendor instead of symlink

We tested four install paths and each handles symlinks differently:

| Install target | File symlinks in plugin | Dir symlinks in plugin |
|---|---|---|
| Claude Code (macOS) | kept as absolute-path symlinks into the marketplace clone | kept |
| Claude Code (Linux) | **silently dropped** — target file is missing at runtime | untested (none in `plugins-claude/`) |
| Copilot CLI (macOS) | dereferenced (copied as real files) | dereferenced |
| Copilot CLI (Linux) | dereferenced | dereferenced |

Claude Code's Linux installer is the odd one out: it copies regular files into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` but skips symlinks entirely, so a `scripts/hook-compat.sh -> ../../../utils/hook-compat.sh` disappears. Every Bash PreToolUse hook then errors with `No such file or directory`. Tracked upstream as [anthropics/claude-code#41392](https://github.com/anthropics/claude-code/issues/41392); until that's fixed, vendoring real copies sidesteps the installer's symlink handling entirely and happens to be the standard pattern for derived files in source control (`Cargo.lock`, `package-lock.json`, generated protobufs, etc.).

### Mechanics

```text
utils/sync.sh         # copy canonical → each plugin's scripts/
utils/sync.sh --check # exit non-zero on drift (CI + pre-commit)
```

- The vendoring manifest is the `NEEDS` associative array at the top of `utils/sync.sh` — a map from plugin name (kebab-case, quoted to survive shfmt) to a space-separated list of util filenames.
- `.github/scripts/validate-plugins.sh` runs `sync.sh --check` so drift fails CI.
- `.githooks/pre-commit` runs the same check locally; opt in with `git config core.hooksPath .githooks` (documented under **Git hooks** below).
- Scripts reference co-located siblings via `$(dirname "$0")/sibling`. Because the copy sits next to the consuming scripts, this resolves at runtime whether the file is canonical or vendored.

### Extending

**Using an existing util in a new plugin:**

1. Add the plugin to `NEEDS` in `utils/sync.sh`:

   ```bash
   ["new-plugin"]="approve-own-scripts.sh hook-compat.sh"
   ```

2. Run `utils/sync.sh`. It copies the utils into `plugins-claude/new-plugin/scripts/`.
3. `git add` the new files and the manifest change. Commit.

**Adding a new shared util:**

1. Drop the canonical file into `utils/`. Make it executable if it's a script (`chmod +x`).
2. Add the filename to the `NEEDS` entry of every plugin that consumes it (existing or new).
3. Run `utils/sync.sh` to vendor it, then commit the util + manifest + vendored copies together.

**Editing a util:**

1. Edit `utils/<file>` — **never** edit the vendored copies directly; the pre-commit hook and CI will block the commit.
2. Run `utils/sync.sh` to propagate.
3. Bump the `version` in `.claude-plugin/plugin.json` for every plugin that consumes the util (both `plugins-claude/<name>/` and `plugins-copilot/<name>/`), otherwise installed clients won't pick up the change.
4. Commit the util, manifest (if changed), vendored copies, and plugin.json bumps together.

## Path References

Use `${CLAUDE_PLUGIN_ROOT}` for all intra-plugin path references:

- In skill content: `${CLAUDE_PLUGIN_ROOT}/scripts/my-tool` (resolved at load time)
- In hook commands: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh` (resolved at execution)
- In MCP configs: `${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh` (resolved at registration)

Never use hardcoded paths like `~/.claude/tools/...`.

## Installation

Install individual plugins from the marketplace:

```bash
claude plugin install agent-toolkit/format-on-save
claude plugin install agent-toolkit/permission-manager
```

Or test locally during development:

```bash
claude --plugin-dir ./plugins-claude/permission-manager
```

## Conventions

- Scripts must be self-contained with no external dependencies beyond standard tools
- End all files with a line feed
- Use kebab-case for all directory and file names
- Skills that are model-triggered (not user-initiated) set `user-invocable: false`
- Scripts reference siblings via `$(dirname "$0")` for co-located files
- Slash command syntax uses colons: `/plugin:command` (not `/plugin command`)
- **Always bump the plugin version** in both `plugins-claude/<name>/.claude-plugin/plugin.json` and `plugins-copilot/<name>/.claude-plugin/plugin.json` when making any changes to a plugin. A patch version bump (e.g. `3.1.0` → `3.1.1`) is sufficient unless the change is a new feature (minor) or breaking (major). Installed plugins won't update without a version change.
- **Prefer reusable utils over plugin-local scripts.** If a script is not specific to one plugin's domain, put it in `utils/`, add it to the `NEEDS` manifest in `utils/sync.sh`, and run the sync to vendor copies into each consuming plugin. Before writing a new script, check whether an existing plugin or util already provides the capability (e.g., `markdown` plugin for linting). Avoid duplicating functionality across plugins.

## Workflow

This is a GitHub-hosted repository. Use `gh` for all GitHub operations (PRs, issues, CI checks).

### Validation

CI runs five independent checks. Run all of them locally with one command:

```bash
bash .github/scripts/validate-all.sh
```

**Prefer that over running the checks by hand.** It is the single source of
truth for what CI enforces, so the list cannot rot the way a copy in this file
does — it previously documented `rumdl .`, which is not a valid invocation and
silently linted nothing, and it omitted shell linting entirely.

The individual checks, if you need to run one in isolation:

```bash
bash test.sh                                   # plugin tests
bash .github/scripts/validate-plugins.sh       # plugin structure
bash .github/scripts/validate-frontmatter.sh   # command/skill frontmatter
rumdl check .                                  # markdown linting
bash .github/scripts/lint-shell.sh             # shellcheck + mock-recursion guard
```

Adding a CI job means adding it to `validate-all.sh` too; the script says so.

Run a single test suite directly:

```bash
bash tests/permission-manager/test-*.sh
```

### Test mocks

Suites that need a fake `git` on `PATH` must use `write_mock_git` from
`tests/lib/mock-git.sh` rather than hand-writing one:

```bash
source "$SCRIPT_DIR/../lib/mock-git.sh"
write_mock_git "$MOCK_DIR" "https://github.com/owner/repo.git"
```

Never delegate unmatched subcommands with `command git "$@"`. `command` bypasses
functions and aliases but **not** `PATH` lookup, so a mock whose directory is
first on `PATH` re-executes itself without bound — this went unnoticed across
nine suites until something called a second git subcommand, then spawned 56k
processes and exhausted the terminal's cgroup pid limit. The shared helper
strips its own directory from `PATH` before delegating and carries a recursion
depth guard; `lint-shell.sh` fails the build if the old form reappears.

### Git hooks

Opt into the repo's pre-commit hooks (checks vendored utils drift) once per clone:

```bash
git config core.hooksPath .githooks
```

Hooks live in `.githooks/` and are tracked in git. The pre-commit hook runs `utils/sync.sh --check` and blocks commits that leave vendored copies out of sync with `utils/`.

### Branching and commits

The `master` branch is protected — never commit directly to it. For all changes:

1. Ensure you're branching from the latest `master`:

   ```bash
   git checkout master && git pull
   ```

2. Create a feature branch with a descriptive name (e.g. `feat/tea-classifier`, `bug/redirect-op-codes`)
3. Commit with a structured message:
   - **Title line**: concise summary in imperative mood (e.g. `feat: add tea CLI classifier to permission-manager`)
   - **Body** (optional, for larger changes): a short paragraph explaining the motivation or context
   - **Bullet list**: specific changes made
4. Push the branch and open a PR via `gh pr create`
5. Monitor the GitHub Actions run (`gh run list`, `gh run view`) — fix any failures and push follow-up commits
6. **Do not manually merge PRs.** A CI bot (`st0nefish-ci`) automatically enables auto-merge (merge commit) on new PRs. Once CI passes, the PR merges on its own.
7. After the PR merges, check out `master` and pull to stay current:

   ```bash
   git checkout master && git pull
   ```

## Copilot CLI Compatibility

Both Claude Code and Copilot CLI recognize the same plugin format (`.claude-plugin/`, `commands/`, `skills/`, `hooks/`). Copilot CLI also supports native extensions discovered from `.github/extensions/<name>/extension.mjs` (project) or `~/.copilot/extensions/<name>/extension.mjs` (user); this repo keeps canonical user-level extension sources under `copilot-extensions/` so they are not auto-loaded as project extensions while you work here. Claude Code strictly validates hook event keys, rejecting the camelCase format Copilot CLI uses. The two CLIs also use different marketplace discovery paths:

| | Claude Code | Copilot CLI |
|---|---|---|
| Marketplace | `.claude-plugin/marketplace.json` | `.github/plugin/marketplace.json` |
| Hook events | PascalCase (`PreToolUse`) | camelCase (`preToolUse`) |
| Hook format | Nested `hooks` array, `command` key | Object `hooks` map, `bash` key, `version: 1` |
| Plugin root var | `${CLAUDE_PLUGIN_ROOT}` | `${COPILOT_PLUGIN_ROOT}` |

**Dual-marketplace approach** — Both marketplaces list nearly all plugins. Copilot CLI uses `plugins-copilot/` variants so hook-enabled plugins can provide a Copilot-format `hooks.json`. Shared directories (scripts, skills, etc.) are symlinked back to the canonical `plugins-claude/` source. The `commands/` directory only exists in `plugins-copilot/` (Claude side has been migrated to skills only) and is always a real directory there — never a symlink:

A handful of surfaces are intentionally CLI-specific:

| Surface | Available on | Why |
|---|---|---|
| `statusline` plugin | Claude only | Configures the Claude Code status line — no Copilot equivalent |
| `git-worktree` extension | Copilot only | Copilot lacks Claude's built-in worktree management; this repo stores its canonical user-level source under `copilot-extensions/git-worktree/` |
| `sf-code-review` plugin | Copilot only | Depends on Copilot CLI cross-family multi-model review orchestration |
| `meal-planning` plugin | Claude only | Non-dev domain plugin; only development plugins are mirrored to Copilot |

### Claude Desktop / Cowork as a consumer surface

Cowork (the agentic tab in Claude Desktop) consumes **the same plugin format as
Claude Code** — `.claude-plugin/marketplace.json` plus `plugin.json`, with
`skills/`, `hooks/`, `agents/`, `commands/`, and `mcp.json`. This repo's
marketplace works there unchanged; no third plugin tree is needed.

Install by adding this repo as a personal marketplace in the app:

> Cowork tab → **Customize** → **Plugins** → *Personal plugins* → **+** →
> **Add from a repository** → `https://github.com/St0nefish/agent-toolkit`

Surface differences that matter when authoring for Cowork:

- Cowork loads plugins from the **claude.ai account**, not `~/.claude`. Adding a
  marketplace in Claude Code does not make it available in Desktop, and vice
  versa — they are separate installs of the same repo.
- Skills and MCP connectors work in both the Chat and Cowork tabs. **Hooks and
  sub-agents run only in Cowork** and appear greyed out in Chat.
- Cowork syncs account-scoped marketplaces **server-side** (the backend clones the
  repo), unlike Claude Code which clones locally into
  `~/.claude/plugins/marketplaces/`. A public repo URL always works; private repos
  require a connected GitHub account with the Claude GitHub App installed — a
  personal access token in the URL is rejected on this path even though the Claude
  Code CLI accepts one. Non-GitHub hosts (GitLab, Bitbucket) are supported as
  generic public git and are account-scoped only.
- Org-level marketplaces (Team/Enterprise, admin-managed) require a *private* repo
  and add install-preference controls (`installed by default` / `available` /
  `required` / `not available`).
- The Cowork marketplace path is feature-gated server-side, so availability can
  vary by account even on a supported plan. If *Add from a repository* is absent,
  that gate — not the repo — is the reason.
- Desktop reads `skills`, `mcpServers`, `hooks`, and `agents` from an installed
  plugin, plus a Desktop-only `clis` field for CLI wrapper declarations. There is
  no separate `commands` field: a legacy `commands/*.md` tree is folded into
  `skills`, which is another reason the Claude side of this repo is skills-only.
- Custom skills do **not** sync across surfaces: a zip uploaded to claude.ai, a
  skill created through the `/v1/skills` API, and a filesystem skill in Claude
  Code are three separate stores. A git-hosted marketplace is the only mechanism
  with one source of truth spanning Chat and Cowork.

```text
plugins-copilot/<name>/
├── .claude-plugin/
│   └── plugin.json          # copy of canonical plugin.json (version kept in sync)
├── hooks/
│   └── hooks.json                # Copilot CLI format (camelCase, object map, version:1)
├── commands/                # real directory — Copilot's user-invocable slash commands
├── scripts -> ../../plugins-claude/<name>/scripts
├── skills -> ../../plugins-claude/<name>/skills
└── <other-dirs> -> ../../plugins-claude/<name>/<other-dirs>
```

The Copilot CLI marketplace (`.github/plugin/marketplace.json`) points to the `-copilot` variants for marketplace plugins. `git-worktree` is intentionally not listed there because it ships as a Copilot extension sourced from `copilot-extensions/git-worktree/`.

**Hook script input** — Claude Code sends `tool_name`/`tool_input` (snake_case); Copilot CLI sends `toolName`/`toolArgs` (camelCase, args as JSON string). Source `hook-compat.sh` to normalize:

```bash
HOOK_INPUT=$(cat)
source "$(dirname "$0")/hook-compat.sh"
# Exports: HOOK_FORMAT, HOOK_TOOL_NAME, HOOK_COMMAND, HOOK_FILE_PATH, HOOK_EVENT_NAME
# hook_ask "reason" / hook_allow "reason" — output correct JSON per CLI
```
