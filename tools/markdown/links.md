---
description: >-
  Check markdown files for broken links (local and web) using lychee.
  REQUIRED for link checking — do NOT run lychee directly.
  Use when validating docs, READMEs, or any markdown files for dead URLs
  or broken local references.
allowed-tools: Bash
---

# Check Links

Validate all links in markdown files using [lychee](https://github.com/lycheeverse/lychee).

## Usage

Check a single file:

```bash
lychee README.md
```

Check a directory:

```bash
lychee docs/
```

Check everything in the repo:

```bash
lychee .
```

## Useful flags

- `--no-progress` — suppress progress bar (cleaner for piped output)
- `--format markdown` — output results as markdown
- `--include-mail` — also validate mailto: links
- `--exclude <regex>` — skip URLs matching a pattern
- `--timeout <secs>` — per-request timeout (default 20s)
- `--max-retries <n>` — retry failed requests (default 3)
- `--accept 200..=299,403` — treat 403s as OK (some sites block bots)

## Typical workflow

1. Run `lychee --no-progress <target>` to find broken links
2. Review the output — links are grouped by status (OK, error, excluded)
3. Fix or remove broken URLs
4. Re-run to confirm fixes

## Notes

- Read-only, safe for auto-approval
- Install: `brew install lychee` (macOS) or `cargo install lychee`
- Respects `.lycheeignore` for permanent exclusions
- Exit code 0 = all links OK, non-zero = failures found
- See also: `/markdown:links-local` (offline only), `/markdown:links-web` (remote only)
