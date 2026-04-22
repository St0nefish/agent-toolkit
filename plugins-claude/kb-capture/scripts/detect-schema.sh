#!/usr/bin/env bash
# detect-schema.sh — Find a frontmatter schema/taxonomy file and extract valid field values.
#
# Searches CWD (maxdepth 3), then walks up to git root, for markdown files
# matching *schema*, *frontmatter*, or *taxonomy* in their name.
# Extracts constrained field values by parsing bullet lists under headings.
#
# Output: JSON on stdout
#   {"schema_file": "path/to/file", "fields": {"type": [...], "domain": [...], ...}}
#   Empty fields if no schema found: {"schema_file": "", "fields": {}}
#
# Exit: always 0 (empty schema is not an error)

set -euo pipefail

find_schema_files() {
  local dir="$1" depth="$2"
  find "$dir" -maxdepth "$depth" -type f -name '*.md' \( \
    -iname '*schema*' -o -iname '*frontmatter*' -o -iname '*taxonomy*' \
    \) 2>/dev/null | head -5
}

# Phase 1: search CWD with shallow depth
candidates=$(find_schema_files "." 3)

# Phase 2: walk up to git root if nothing found
if [[ -z "$candidates" ]]; then
  git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$git_root" && "$git_root" != "$(pwd)" ]]; then
    dir=$(pwd)
    while [[ "$dir" != "$git_root" && "$dir" != "/" ]]; do
      dir=$(dirname "$dir")
      candidates=$(find_schema_files "$dir" 1)
      if [[ -n "$candidates" ]]; then
        break
      fi
    done
  fi
fi

# Pick the first candidate
schema_file=$(echo "$candidates" | head -1)

if [[ -z "$schema_file" ]]; then
  echo '{"schema_file": "", "fields": {}}'
  exit 0
fi

# Parse the schema file: extract field headings and their bullet-list values.
# Looks for patterns like:
#   ## Available type     or    ### type     or    ## type:
# Followed by bullet lines:
#   - value1
#   - value2
# Or inline comma-separated after a colon:
#   Available type: guide, reference, research

fields_json="{"
first_field=true
current_field=""
values=""

while IFS= read -r line; do
  # Check for heading that names a field
  if [[ "$line" =~ ^#{1,4}[[:space:]]+(Available[[:space:]]+)?([a-zA-Z_-]+):?[[:space:]]*$ ]]; then
    # Save previous field
    if [[ -n "$current_field" && -n "$values" ]]; then
      if [[ "$first_field" == "true" ]]; then
        first_field=false
      else
        fields_json+=","
      fi
      json_array=$(echo "$values" | jq -R -s 'split("\n") | map(select(length > 0))')
      fields_json+="\"$current_field\": $json_array"
    fi
    current_field="${BASH_REMATCH[2]}"
    current_field=$(echo "$current_field" | tr '[:upper:]' '[:lower:]')
    values=""
    continue
  fi

  # Check for inline values after heading-like pattern: "Available type: val1, val2, val3"
  if [[ "$line" =~ ^#{1,4}[[:space:]]+(Available[[:space:]]+)?([a-zA-Z_-]+):[[:space:]]+(.+)$ ]]; then
    field="${BASH_REMATCH[2]}"
    field=$(echo "$field" | tr '[:upper:]' '[:lower:]')
    inline_vals="${BASH_REMATCH[3]}"

    # Save previous field first
    if [[ -n "$current_field" && -n "$values" ]]; then
      if [[ "$first_field" == "true" ]]; then
        first_field=false
      else
        fields_json+=","
      fi
      json_array=$(echo "$values" | jq -R -s 'split("\n") | map(select(length > 0))')
      fields_json+="\"$current_field\": $json_array"
    fi

    # Parse comma-separated inline values
    if [[ "$first_field" == "true" ]]; then
      first_field=false
    else
      fields_json+=","
    fi
    json_array=$(echo "$inline_vals" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R -s 'split("\n") | map(select(length > 0))')
    fields_json+="\"$field\": $json_array"
    current_field=""
    values=""
    continue
  fi

  # Collect bullet values under current heading
  if [[ -n "$current_field" ]]; then
    if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.+)$ ]]; then
      value="${BASH_REMATCH[1]}"
      # Strip trailing whitespace and backticks
      value=$(echo "$value" | sed 's/`//g;s/[[:space:]]*$//')
      values+="$value"$'\n'
    elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
      # Blank line — continue collecting (might be spacing between bullets)
      :
    elif [[ ! "$line" =~ ^[[:space:]]*[-*] && ! "$line" =~ ^# ]]; then
      # Non-bullet, non-heading line — stop collecting for this field
      :
    fi
  fi
done <"$schema_file"

# Save last field
if [[ -n "$current_field" && -n "$values" ]]; then
  if [[ "$first_field" == "true" ]]; then
    first_field=false
  else
    fields_json+=","
  fi
  json_array=$(echo "$values" | jq -R -s 'split("\n") | map(select(length > 0))')
  fields_json+="\"$current_field\": $json_array"
fi

fields_json+="}"

# Build final output
jq -n --arg sf "$schema_file" --argjson fields "$fields_json" \
  '{"schema_file": $sf, "fields": $fields}'
