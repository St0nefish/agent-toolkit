---
description: >-
  Check markdown files for broken local/file links only (offline). REQUIRED
  for local link validation — do NOT run lychee --offline directly.
  Use when validating internal cross-references, relative paths, and anchor
  links without hitting the network.
---

# Check Local Links

Validate local file links and anchors in markdown using [lychee](https://github.com/lycheeverse/lychee) in offline mode.

## Usage

Check a single file:

```bash
lychee --offline README.md
```

Check a directory:

```bash
lychee --offline docs/
```

Check everything in the repo:

```bash
lychee --offline .
```

## Notes

- Read-only, safe for auto-approval
- No network access — only checks file paths and anchors
- Fast — no HTTP timeouts or retries
- Exit code 0 = all local links OK, non-zero = failures found
- See also: `/markdown:links` (all links), `/markdown:links-web` (remote only)
