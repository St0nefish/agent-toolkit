#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/hook-compat.sh"

if [[ "$HOOK_FORMAT" == "claude" ]]; then
    hook_allow "Maven toolkit scripts"
else
    hook_allow "Maven toolkit scripts"
fi