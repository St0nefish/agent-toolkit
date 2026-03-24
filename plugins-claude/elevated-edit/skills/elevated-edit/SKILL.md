---
user-invocable: true
name: elevated-edit
description: >-
  Edit files that require elevated privileges or are on a remote host via SSH.
  Use when: the user wants to edit a file on a remote server; editing fails
  with "Permission denied"; the target is in /etc/, /usr/, /var/, /opt/, or
  any system directory; the file is owned by root or another user; the user
  mentions SSH file editing, remote config files, or privileged file access;
  or when an Edit or Write tool call fails due to file permissions.
allowed-tools: Bash, Read, Edit, Write
---

Edit files across SSH or sudo boundaries using a pull/edit/push workflow.

### Workflow

1. **Pull** the file to a local temp directory:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge pull [user@host:]path
   ```

   For new files that don't exist yet:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge pull --new [--owner root:root] [--mode 0644] [user@host:]path
   ```

2. **Read** the temp file path printed by the pull command, then **Edit** or **Write** it normally — the standard diff view and approval UI work as usual.

3. **Push** changes back to the original location:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge push /tmp/elevated-edit/<session>/path/to/file
   ```

   Original ownership and permissions are automatically restored from the `.meta` sidecar.

### Examples

**Local privileged file:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge pull /etc/nginx/nginx.conf
# Read and Edit the temp file...
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge push /tmp/elevated-edit/XXXXXX/etc/nginx/nginx.conf
```

**Remote file via SSH:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge pull admin@webserver:/etc/nginx/nginx.conf
# Read and Edit the temp file...
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge push /tmp/elevated-edit/XXXXXX/etc/nginx/nginx.conf
```

**Push by original source path** (finds the most recent session):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge push /etc/nginx/nginx.conf
bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge push admin@webserver:/etc/nginx/nginx.conf
```

### Notes

- **Binary files:** rsync handles binary files fine, but do not attempt to Edit binary content — use Read to inspect and Write for full replacement only.
- **Large files:** rsync handles large files efficiently; Read/Edit work on the local temp copy.
- **Symlinks:** rsync follows symlinks by default. The pushed file replaces the symlink target.
- **Sudo NOPASSWD:** For local privileged files, the script uses `sudo rsync`. If sudo prompts for a password, configure NOPASSWD for rsync or cache credentials with `sudo -v` before pulling.
- **Cleanup:** Sessions are auto-cleaned after a successful push. To clean abandoned sessions: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-bridge clean --stale` (>24h) or `clean --all`.
- **Permission-manager users:** Add an allow pattern to `~/.claude/command-permissions.json` for frictionless operation:

  ```json
  { "allow": ["bash */scripts/file-bridge *"] }
  ```
