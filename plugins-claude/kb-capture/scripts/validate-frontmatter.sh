#!/usr/bin/env bash
# validate-frontmatter.sh — Validate a markdown file's YAML frontmatter against schema.
#
# Usage: validate-frontmatter.sh <file>
#
# Checks:
#   - Frontmatter block exists (--- delimited)
#   - Required fields present: title, date
#   - Date format: YYYY-MM-DD
#   - Constrained fields match schema values (via detect-schema.sh)
#
# Exit codes:
#   0 = valid
#   1 = violations found (printed to stdout)
#   2 = usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: validate-frontmatter.sh <file>" >&2
  exit 2
fi

file="$1"

if [[ ! -f "$file" ]]; then
  echo "Error: file not found: $file" >&2
  exit 2
fi

# Extract frontmatter (between first two --- lines)
frontmatter=$(awk '
  /^---[[:space:]]*$/ {
    if (count == 0) { count++; next }
    if (count == 1) { exit }
  }
  count == 1 { print }
' "$file")

if [[ -z "$frontmatter" ]]; then
  echo "FAIL: no YAML frontmatter found (missing --- delimiters)"
  exit 1
fi

violations=()

# Check required field: title
title=$(echo "$frontmatter" | grep -E '^title:' | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
if [[ -z "$title" ]]; then
  violations+=("missing required field: title")
fi

# Check required field: date
date_val=$(echo "$frontmatter" | grep -E '^date:' | head -1 | sed 's/^date:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
if [[ -z "$date_val" ]]; then
  violations+=("missing required field: date")
elif [[ ! "$date_val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  violations+=("invalid date format: '$date_val' (expected YYYY-MM-DD)")
fi

# Load schema for constrained field validation
schema_json=$("$SCRIPT_DIR/detect-schema.sh" 2>/dev/null || echo '{"schema_file": "", "fields": {}}')
schema_fields=$(echo "$schema_json" | jq -r '.fields // {}')

# Validate constrained fields (type, domain, status)
for field in type domain status; do
  valid_values=$(echo "$schema_fields" | jq -r ".\"$field\" // [] | .[]" 2>/dev/null)
  if [[ -z "$valid_values" ]]; then
    continue
  fi

  file_value=$(echo "$frontmatter" | grep -E "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^["'"'"']//;s/["'"'"']$//')
  if [[ -z "$file_value" ]]; then
    continue
  fi

  if ! echo "$valid_values" | grep -qxF "$file_value"; then
    allowed=$(echo "$valid_values" | paste -sd', ' -)
    violations+=("invalid $field: '$file_value' (allowed: $allowed)")
  fi
done

if [[ ${#violations[@]} -gt 0 ]]; then
  for v in "${violations[@]}"; do
    echo "FAIL: $v"
  done
  exit 1
fi

echo "OK: frontmatter is valid"
exit 0
