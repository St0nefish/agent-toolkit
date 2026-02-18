---
description: >-
  Check markdown files for broken web/HTTP links only (skips local files).
  REQUIRED for remote link validation — do NOT run lychee --scheme directly.
  Use when validating external URLs without checking local file references.
---

# Check Web Links

Validate only HTTP/HTTPS links in markdown using [lychee](https://github.com/lycheeverse/lychee).

## Usage

Check a single file:

```bash
lychee --scheme https --scheme http README.md
```

Check a directory:

```bash
lychee --scheme https --scheme http docs/
```

Check everything in the repo:

```bash
lychee --scheme https --scheme http .
```

## Useful flags

- `--no-progress` — suppress progress bar (cleaner for piped output)
- `--exclude <regex>` — skip URLs matching a pattern
- `--timeout <secs>` — per-request timeout (default 20s)
- `--max-retries <n>` — retry failed requests (default 3)
- `--accept 200..=299,403` — treat 403s as OK (some sites block bots)

## Notes

- Read-only, safe for auto-approval
- Only checks http:// and https:// links — skips file paths and anchors
- Exit code 0 = all web links OK, non-zero = failures found
- See also: `/markdown:links` (all links), `/markdown:links-local` (offline only)
