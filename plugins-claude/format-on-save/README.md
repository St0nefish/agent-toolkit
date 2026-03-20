# Format on Save

Auto-formats files after every Edit or Write using language-appropriate formatters. Runs asynchronously so it never blocks Claude.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/format-on-save
```

## Supported Formatters

| Extensions | Formatter | Install |
|------------|-----------|---------|
| `.sh`, `.bash` | `shfmt` | `brew install shfmt` |
| `.js`, `.ts`, `.jsx`, `.tsx`, `.json`, `.yml`, `.yaml`, `.css`, `.html` | `prettier` | `npm install -g prettier` |
| `.md` | `rumdl` | `cargo install rumdl` or `brew install rumdl` |
| `.java` | `google-java-format` | `brew install google-java-format` |
| `.kt`, `.kts` | `ktlint` | `brew install ktlint` |
| `.rs` | `cargo fmt` / `rustfmt` | Included with Rust toolchain |
| `.toml` | `taplo` | `cargo install taplo-cli` |
| `.py`, `.pyi` | `ruff` | `pip install ruff` or `brew install ruff` |

Only install the formatters you need. Missing formatters are skipped with a warning — the hook never fails.

For Rust files, the hook walks up the directory tree looking for `Cargo.toml` and runs `cargo fmt` on the workspace. Falls back to `rustfmt` on the single file if no `Cargo.toml` is found.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | Hook payload parsing (via `hook-compat.sh`) |
| Formatters above | No | Each is optional — install what you need |
