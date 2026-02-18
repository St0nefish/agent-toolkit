---
allowed-tools: Bash, Read
description: >-
  Paste an image from the Windows clipboard. Use when the user says "paste",
  "screenshot", "clipboard image", or wants to share an image from their
  clipboard. Saves to /tmp with content-hash deduplication and returns the
  file path.
---

Execute `~/.claude/tools/paste-image-wsl/bin/paste-image` to extract an image from the Windows clipboard. The script outputs the path to the saved image file. Read that image file and display it to the user. Be concise.
