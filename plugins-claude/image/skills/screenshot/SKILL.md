---
name: image-screenshot
allowed-tools: Bash, Read
description: >-
  Read the most recent screenshot. Use when the user says "screenshot",
  "latest screenshot", or wants to view a recent screen capture. Returns
  the file path.
---

Execute `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot` to find the most recent screenshot. The script outputs the path to the newest `.png` file. Read that image file and display it to the user. Be concise.
