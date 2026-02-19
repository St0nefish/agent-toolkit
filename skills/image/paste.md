---
allowed-tools: Bash, Read
description: >-
  Paste an image from the clipboard. Use when the user says "paste",
  "clipboard image", or wants to share an image from their clipboard.
  Works on macOS (pngpaste), WSL (PowerShell), and Linux (wl-paste / xclip).
  Saves to /tmp with content-hash deduplication and returns the file path.
---

Execute `~/.claude/tools/image/bin/paste-image` to extract an image from the clipboard. The script outputs the path to the saved image file. Read that image file and display it to the user. Be concise.
