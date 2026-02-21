# deploy-rs

Rust reimplementation of `deploy-py/deploy.py`. Produces a binary named `deploy` that is functionally equivalent to the Python deployer, plus adds an interactive TUI mode.

For the deployment config format, skill authoring patterns, and overall repo layout, see the root `CLAUDE.md`.

## Build and Run

```bash
# From repo root or deploy-rs/ directory
cargo build --manifest-path deploy-rs/Cargo.toml         # debug build
cargo build --manifest-path deploy-rs/Cargo.toml --release

# Run directly
cargo run --manifest-path deploy-rs/Cargo.toml           # bare = TUI if TTY
cargo run --manifest-path deploy-rs/Cargo.toml -- --dry-run
cargo run --manifest-path deploy-rs/Cargo.toml -- --help

# Or run the compiled binary
./deploy-rs/target/debug/deploy --dry-run
./deploy-rs/target/release/deploy
```

The convenience `./deploy` wrapper at the repo root still calls the Python deployer. The Rust binary is `deploy-rs/target/[debug|release]/deploy`.

## Testing

```bash
# All tests (unit + integration)
bash deploy-rs/test.sh

# With filters
bash deploy-rs/test.sh -- --test deploy_symlinks
bash deploy-rs/test.sh -- config::tests

# Direct cargo
cargo test --manifest-path deploy-rs/Cargo.toml
```

Integration tests (`tests/*.rs`) run the compiled binary against a temp directory repo. They use `MiniRepo` from `tests/common/mod.rs` to build minimal fixture repos, run `deploy` via `Command::new`, and assert on resulting symlink/file state. `CLAUDE_CONFIG_DIR` env var is always set to a temp dir to avoid touching real config.

Unit tests live inline in source files using `#[cfg(test)]` modules.

## Project Structure

```
src/
  main.rs               — Entry point; routes bare/TTY invocations to TUI,
                          else to headless CLI
  cli.rs                — CLI argument parsing (clap derive), DeployContext,
                          execute_deploy() orchestrator, find_repo_root()
  config.rs             — Config loading, 5-layer merge, profile overrides
  discovery.rs          — Item discovery (skills/hooks/mcp/permissions) and
                          profile diff
  linker.rs             — ensure_link(), cleanup_broken_symlinks()
  permissions.rs        — Permission collection, sort-key grouping table
  settings.rs           — Atomic read-modify-write for settings.json
                          (permissions, hooks, mcpServers)
  deploy/
    mod.rs              — Re-exports submodules
    skills.rs           — deploy_skill(), collect_skills() (skill layout detection)
    hooks.rs            — deploy_hook()
    mcp.rs              — deploy_mcp(), teardown_mcp()
    permission_groups.rs — deploy_permission_groups()
  tui/
    mod.rs              — Re-exports run_tui
    app.rs              — Pure state machine: App struct, all business logic,
                          no terminal I/O
    events.rs           — Crossterm event loop, terminal setup/teardown,
                          deploy execution, stdout capture
    state.rs            — TuiState persistence (.deploy-tui-state.json)
    ui.rs               — Stateless ratatui rendering
tests/
  common/mod.rs         — MiniRepo test helper
  deploy_symlinks.rs    — Symlink creation/layout tests
  deploy_config.rs      — Config merge and layer tests
  deploy_filtering.rs   — --include / --exclude tests
  deploy_hooks.rs       — Hook deployment tests
  deploy_mcp.rs         — MCP deployment tests
  deploy_permissions.rs — Permission merge and settings.json tests
  deploy_permission_groups.rs — Permission group deployment tests
  deploy_dependencies.rs — Skill dependency tests
  deploy_cli_validation.rs — CLI flag validation tests
```

## Key Types

**`cli.rs`**
- `Cli` — clap `Parser` derive struct for all flags
- `DeployContext` — shared context for one deploy pass (repo root, config dir, flags, include/exclude, profile data, per-script PATH map). Used by both CLI and TUI
- `DeploySummary` — output of `execute_deploy()`
- `execute_deploy(ctx)` — main orchestrator: walks skills/, hooks/, mcp/, permissions/, calls deploy functions, updates settings.json
- `find_repo_root()` — walks ancestors looking for a `skills/` directory
- `resolve_claude_config_dir()` — respects `CLAUDE_CONFIG_DIR` env var (used by tests)

**`config.rs`**
- `DeployConfig` — `Option`-fielded config struct for merge semantics
- `ResolvedConfig` — concrete values after merge and defaults applied
- `DeployConfig::merge(self, other)` — `other` wins for any `Some` field
- `resolve_config(item_dir, repo_root)` — loads and merges all 5 layers
- `apply_profile_overrides(config, profile_data, item_type, item_name)` — profile is authoritative; items not listed are disabled

**`deploy/skills.rs`**
- `SkillDeployCtx<'a>` — borrow-heavy context struct passed to `deploy_skill()`
- `collect_skills(skill_dir, skill_name)` — implements legacy vs. modern layout detection; modern wins if both are present

**`tui/app.rs`**
- `App` — all TUI state: tab cursor, row data, modal state, deploy output, scroll offset
- `AssignedMode` — `Global | Project(Vec<String>) | Skip` — the core per-item deployment target
- `SkillRow` / `SimpleRow` / `ScriptEntry` / `ProjectEntry` — row data types
- `InputMode` — TUI state machine mode: `Normal | AddProject | EditAlias | SelectProjects | ScriptConfig | InfoView | DryRunning | Confirming | Deploying | Done`
- `DeployPlan` — built from App state; passed to `execute_deploy()` as include lists
- `DeployResults` / `AggregatedResult` / `DeployStatus` — aggregated multi-pass deploy results

**`tui/events.rs`**
- `run_tui()` — terminal setup, event loop, teardown, state save
- `execute_plan()` — runs one global pass + N project passes via `execute_deploy()`
- `capture_stdout()` — redirects fd 1 via `libc::dup2` to capture deploy output while TUI holds the terminal

**`tui/state.rs`**
- `TuiState` — persisted to `.deploy-tui-state.json` at repo root
- `capture_state(app)` / `apply_state(app, state)` — save/restore round-trip

## TUI

**Auto-launch logic (`main.rs`):** bare invocation (`./deploy`) with a TTY launches the TUI. `--interactive` forces TUI even with other args. Otherwise headless CLI.

**Tab layout:** Skills | Hooks | MCP | Permissions.

**Key bindings (Normal mode):**
- `Tab` / `Shift+Tab`, `Left` / `Right`, `h` / `l` — cycle tabs
- `j` / `k` or arrow keys — navigate rows
- `Space` — cycle item mode (Global → Project → Skip → Global)
- `P` — open project selector modal
- `T` — open script PATH config modal (Skills tab, Global mode only)
- `I` — open info view (README.md or deploy.json content)
- `a` — select all global
- `s` — skip all
- `Enter` — build deploy plan, show preview, enter Confirming mode
- `q` / `Esc` — quit

**Deploy flow:** `Enter` → `build_preview()` → `InputMode::Confirming` → `y` → `execute_plan()` → `InputMode::Done`.

## Error Handling

- `anyhow::Result` throughout for propagated errors. `main()` converts to `eprintln!` + `exit(1)`.
- `thiserror` is a dependency but not currently used for custom error types; everything uses `anyhow::bail!` or `?`.
- Config and JSON load errors are silent (return empty object/default) — missing files are treated as no-ops.
- MCP `setup.sh` failures are warnings (printed, deploy continues, MCP config not registered).
- Settings writes use atomic rename: write to `.tmp` then `rename`.

## CLI Argument Parsing

Uses clap 4 derive. Multi-value args (`--include`, `--exclude`, `--teardown-mcp`) accept comma-delimited or space-separated values via `value_delimiter = ','`. A `normalize_list()` helper additionally splits on commas post-parse for safety.

## Config Merge Pattern

The 5-layer merge is consistently applied everywhere:

```
1. hardcoded defaults (enabled=true, scope=global, on_path=false)
2. repo-root deploy.json
3. repo-root deploy.local.json
4. item-level deploy.json
5. item-level deploy.local.json
```

Implemented as `DeployConfig::merge(self, other)` where each field uses `other.field.or(self.field)` for higher-priority-wins semantics. Called sequentially for each layer. Profile data (if any) is applied on top via `apply_profile_overrides()`.

## Conventions

- All source files start with a `// filename.rs - description` comment.
- `dry_run: bool` is threaded through all deploy functions; prints `> cmd` instead of executing.
- Symlink operations go through `ensure_link(link, target, label, dry_run, for_dir)` in `linker.rs`.
- Settings updates use append-missing semantics: existing entries in `settings.json` are preserved; only new entries are added.
- `serde_json` is used with the `preserve_order` feature so `settings.json` key order is stable.
- Unix-only: `#[cfg(unix)]` guards on symlink and file permission operations; `#[cfg(not(unix))]` stubs bail with an error.
- Tests that need disk access use `tempfile::TempDir`; pure-logic unit tests avoid disk entirely.
