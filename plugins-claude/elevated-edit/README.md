# Elevated Edit

Edit files that require elevated privileges or live on a remote host. Model-triggered — fires when editing fails with "Permission denied" or targets system directories (`/etc/`, `/usr/`, `/var/`, `/opt/`).

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/elevated-edit
```

## How It Works

Uses a pull/edit/push workflow via rsync:

1. **Pull** — copies the file to a local temp directory (`/tmp/elevated-edit/`), records original owner/group/mode in a sidecar `.meta` file
2. **Edit** — Claude edits the temp copy with normal Read/Edit/Write tools
3. **Push** — rsync copies back, restoring original ownership and permissions

Works for both local privileged files (via sudo) and remote files (via SSH).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `FILE_BRIDGE_TMPBASE` | `/tmp/elevated-edit` | Base directory for temp sessions |
| `FILE_BRIDGE_DRY_RUN` | (unset) | Set to enable dry-run mode |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `rsync` | Yes | File transfer and permission restoration |
| `jq` | Yes | Metadata handling |
| `ssh` | For remote files | Remote host access |

For local privileged files, sudo NOPASSWD for rsync is recommended.
