---
name: image-paste
allowed-tools: Bash, Read
description: >-
  Paste an image from the clipboard. Use when the user says "paste",
  "clipboard image", or wants to share a clipboard image. Returns the
  saved file path.
---

Execute `${CLAUDE_PLUGIN_ROOT}/scripts/paste-image` to extract an image from the clipboard. The script outputs the path to the saved image file. Read that image file and display it to the user. Be concise.
