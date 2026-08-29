#!/usr/bin/env bash
# lint-shell.sh — shellcheck every shell script in the repo.
#
# Extracted from .github/workflows/ci.yml so the check is reproducible
# locally. CI calls this script; do not re-inline the logic into the workflow.
#
# Usage: bash .github/scripts/lint-shell.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if ! command -v shellcheck >/dev/null 2>&1; then
  # Missing shellcheck is a hard failure in CI — skipping there would turn a
  # broken runner image into a silently green build. Locally it is a warning,
  # so the script stays usable without forcing an install.
  if [[ -n "${CI:-}" ]]; then
    echo "shellcheck not installed and CI is set — refusing to skip" >&2
    exit 1
  fi
  echo "shellcheck not installed — skipping (CI still enforces it)" >&2
  echo "  install: sudo pacman -S shellcheck | brew install shellcheck" >&2
  exit 0
fi

# Collect .sh files (exclude symlinks to avoid double-checking)
mapfile -t scripts < <(find . -name '*.sh' -not -path './.git/*' -not -type l | sort)

# Collect extensionless scripts in scripts/ dirs (exclude symlinks)
while IFS= read -r f; do
  [[ -L "$f" ]] && continue
  if head -1 "$f" 2>/dev/null | grep -qE '^#!/.*(bash|sh)'; then
    scripts+=("$f")
  fi
done < <(find . -path '*/scripts/*' -not -name '*.*' -not -path './.git/*' -type f | sort)

if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "No shell scripts found"
  exit 0
fi

echo "Checking ${#scripts[@]} script(s)..."
shellcheck --severity=error "${scripts[@]}"

# Backstop: a PATH-injected mock must never delegate with `command <tool>`.
# `command` bypasses functions and aliases but NOT PATH lookup, so a mock whose
# directory is first on PATH re-executes itself without bound. Use
# tests/lib/mock-git.sh, which strips its own directory from PATH and carries a
# recursion depth guard.
if grep -rn --include='*.sh' -E '\)\s*command (git|gh|tea) ' tests/ 2>/dev/null; then
  echo "" >&2
  echo "ERROR: mock delegates via 'command <tool>' — this recurses through PATH." >&2
  echo "Use write_mock_git from tests/lib/mock-git.sh instead." >&2
  exit 1
fi
