---
allowed-tools: Bash, Read
description: >-
  Paste an image from the macOS clipboard. Use when the user says "paste",
  "clipboard image", or wants to share an image from their clipboard on macOS.
  Saves to /tmp with content-hash deduplication and returns the file path.
  Requires pngpaste (brew install pngpaste).
---

Execute `~/.claude/tools/paste-image-macos/bin/paste-image` to extract an image from the macOS clipboard. The script outputs the path to the saved image file. Read that image file and display it to the user. Be concise.
