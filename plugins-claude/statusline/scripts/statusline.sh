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

cat "${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/$id" 2>/dev/null
exit 0
