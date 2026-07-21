---
name: freecad-live
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit
description: >-
  Start or stop a live FreeCAD design session — the model rebuilds in the open
  window as the script changes, with the camera left where you put it.
---

# Live FreeCAD session

Argument: a model script (`.py`). With no argument, find the most recently
modified model script under the working directory and confirm it with the user
before starting.

## Start

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/fclive -b <model.py>
```

Then wait for the first build and report the result:

```bash
until grep -qa "rebuild #1 ok\|rebuild FAILED" "$WW_LOG"; do sleep 2; done
```

`fclive` prints the log path. Read it for build output — under the GUI, FreeCAD
sends `print()` to its Report View rather than stdout, so the log file is the
only channel that works.

On macOS the window opens unfocused and cannot be raised programmatically
(the binary is launched directly so it inherits the session's environment, which
means LaunchServices never registers it). Tell the user to Cmd-Tab to it.

## Iterate

Edit the model script. The watcher rebuilds within a second, preserving the
user's camera. Do not restart FreeCAD to pick up a change — including changes to
`wwkit` itself, which the watcher reloads.

Before handing a change back, render it and look at it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/fcrender <doc>.FCStd renders/ iso,top
```

## Stop

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/fcquit <model.py>
```

Never `kill` FreeCAD. A hard kill leaves recovery state that blocks the next
launch behind a modal dialog you cannot see.

## If navigation feels broken

`fclive` now sets sane defaults on first build — **Gesture** navigation (trackpad
friendly: left-drag rotates, two-finger drag pans, scroll zooms), **Turntable**
orbit (spins about vertical and keeps "up", instead of Trackball tumbling), and
rotate-about-cursor. If it still feels off, the navigation style is the dropdown
in the status bar (bottom right). Spacebar toggles visibility of the tree
selection, which is how you isolate a part.
