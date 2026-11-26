---
name: image-paste
allowed-tools: Bash, Read
description: >-
  Save the image on the clipboard to a file and show it. Use when the user asks
  to paste or look at a clipboard image, a screenshot they copied, or "what I
  just copied" when it is an image. Not for pasted text, and not for the latest
  screenshot file (use image-screenshot).
---

Execute `${CLAUDE_PLUGIN_ROOT}/scripts/paste-image` to extract an image from the clipboard. The script outputs the path to the saved image file. Read that image file and display it to the user. Be concise.
