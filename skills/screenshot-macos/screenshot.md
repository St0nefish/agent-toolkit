---
allowed-tools: Bash, Read
description: >-
  Find and read the most recent screenshot on macOS. Use when the user says
  "screenshot", "latest screenshot", or wants to view a recent screen capture.
  Looks in ~/Pictures/Screenshots by default (override with SCREENSHOTS_DIR).
---

Execute `~/.claude/tools/screenshot-macos/bin/screenshot` to find the most recent screenshot. The script outputs the path to the newest `.png` file. Read that image file and display it to the user. Be concise.
