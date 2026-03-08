---
name: image-screenshot
allowed-tools: Bash, Read
description: >-
  Find and read the most recent screenshot. Use when the user says
  "screenshot", "latest screenshot", or wants to view a recent screen capture.
  Works on macOS, WSL, and Linux. Looks in the platform default screenshots
  directory (override with SCREENSHOTS_DIR).
---

Execute `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot` to find the most recent screenshot. The script outputs the path to the newest `.png` file. Read that image file and display it to the user. Be concise.
