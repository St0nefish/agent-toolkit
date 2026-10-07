---
disable-model-invocation: true
name: statusline-config
description: "Show how to choose a status line style"
allowed-tools: Bash
---

# Status Line Config

Version 3 of the status line is a mod, so it is configured through Claude Code's
plugin options rather than a `config.json`.

## Instructions

1. Show the user the current option and what is available:

   ```bash
   claude plugin configure statusline@agent-toolkit
   ```

2. Explain the styles:

   | Style | Where | Notes |
   |-------|-------|-------|
   | `below` (default) | Under the prompt | Coloured, via the `statusLine` slot; needs the stub from `/statusline:statusline-setup` |
   | `flat-left` | Above the prompt | Flat text packed left; needs no `statusLine` setup |
   | `powerline` | Above the prompt | One dark band with Nerd Font arrows |
   | `plain` | Above the prompt | Coloured text with thin bars; no patched font needed |

3. To change it, tell the user to run `/config` and edit the statusline style, or
   save a value directly:

   ```bash
   printf '{"style":"flat-left"}' | claude plugin configure statusline@agent-toolkit --values-stdin
   ```

   Only run the second form if the user names the style they want.

   The same command takes `gitPollSeconds` (default `3`, `0` turns the idle git
   check off), for example `{"gitPollSeconds":0}`.

4. The change reloads the module on its own; no restart is needed.

An old `~/.config/claude-statusline/config.json` from before version 3 is no
longer read and can be deleted.
