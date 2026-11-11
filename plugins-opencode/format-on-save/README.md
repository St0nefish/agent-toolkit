# format-on-save (OpenCode)

Config-only port of the Claude `format-on-save` hook. **No code, no plugin** —
OpenCode's built-in `formatter` runs after `write`/`edit`/`patch`, which is
exactly what the Claude `PostToolUse` hook did.

The `formatter` object in [`opencode.jsonc`](opencode.jsonc) mirrors the repo's
dispatch table (same tools, same flags, same extension set) so a file formatted
by either harness is byte-identical. A parity test
(`tests/opencode/test-format-on-save-parity.sh`) fails CI if the Claude script
and this snippet ever disagree.

## Install

Copy the `formatter` object from [`opencode.jsonc`](opencode.jsonc) into your
global `~/.config/opencode/opencode.jsonc` (mirrors the global Claude plugin)
or a project `opencode.jsonc` (stricter: shared repos all get the same rules).

Formatters are **opt-in** in OpenCode: setting the `formatter` object is what
enables them. A bare `"formatter": true` enables OpenCode's built-in defaults
instead, which differ from this repo's (prettier claims `.md`/`.toml`, shfmt
flags differ, bare `rustfmt` ≠ `cargo fmt`).

## Parity notes

- **Never blocks**: OpenCode logs a formatter failure and keeps the edit —
  same always-exit-0 behavior as the hook.
- **Missing tool → skip**: built-ins run only when their executable is found;
  a custom command that isn't found fails and is skipped.
- **`.rs` divergence (accepted)**: the hook prefers `cargo fmt` from the
  nearest `Cargo.toml`; OpenCode formatters are per-file, so this uses
  `rustfmt "$FILE"`. `rustfmt` still reads `rustfmt.toml` upward; only the
  cargo manifest walk is not replicated.
- **Built-in detection rules**: OpenCode gates some built-ins on project
  context (e.g. built-in `prettier` wants a `prettier` dependency in
  `package.json`, `ruff` wants a Ruff config). The Claude hook only checks
  `command -v`. In a project without those markers, prettier/ruff may not run
  in OpenCode even when installed globally — add the project marker or accept
  the skip.
