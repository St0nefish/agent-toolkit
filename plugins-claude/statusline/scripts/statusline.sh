#!/bin/bash
# statusLine command: print the line the statusline mod rendered for this session.
#
# The mod (hooks/register.tsx) does all the work: git, usage, context, cost. It
# can draw coloured text above the prompt but not under it, so it writes the
# finished ANSI line to a per-session file and this stub hands it to Claude
# Code's statusLine slot, which is the one place that draws coloured text below
# the prompt. Nothing here polls, caches or parses anything beyond the id.
#
# Claude Code passes the session as JSON on stdin; only session_id is read, with
# sed so the stub needs no jq.

set -u

id=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[[ -n "$id" && "$id" != */* ]] || exit 0

file="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/$id"

# A fresh session runs this command before the mod's session.start has written
# the file, so wait briefly for it instead of printing nothing until the next
# refresh.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  [[ -s "$file" ]] && break
  sleep 0.1
done

cat "$file" 2>/dev/null
exit 0
