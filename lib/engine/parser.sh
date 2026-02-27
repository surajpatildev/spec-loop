#!/usr/bin/env bash
# spec-loop output parser — extract status, tags, and metrics from Claude output

# Extract text content from stream-json output
# Falls back to raw file if jq fails
extract_parseable_text() {
  local file="$1"

  [[ -s "$file" ]] || return

  if command -v jq >/dev/null 2>&1; then
    local parsed
    parsed=$(jq -r '
      if .type == "result" then (.result // "")
      elif .type == "assistant" then (.message.content[]? | select(.type == "text") | .text // "")
      else ""
      end
    ' "$file" 2>/dev/null || true)

    if [[ -n "$parsed" ]]; then
      printf '%s\n' "$parsed"
      return
    fi
  fi

  # Fallback: treat as plain text
  cat "$file"
}

# Parse a key-value line from output: "KEY: value"
parse_kv_value() {
  local key="$1"
  local file="$2"

  [[ -s "$file" ]] || { echo ""; return; }

  extract_parseable_text "$file" | awk -v prefix="$key: " 'index($0, prefix) == 1 && !found { value = substr($0, length(prefix) + 1); found=1 } END { print value }'
}

# Check if output contains a <promise>TAG</promise>
output_has_tag() {
  local file="$1"
  local tag="$2"

  [[ -s "$file" ]] || return 1

  extract_parseable_text "$file" | grep -q "^<promise>${tag}</promise>$"
}

# Extract cost from result event
extract_cost() {
  local file="$1"

  [[ -s "$file" ]] || { echo "0"; return; }

  local raw
  raw=$(jq -r 'select(.type == "result") | .total_cost_usd // 0' "$file" 2>/dev/null | tail -1)
  echo "${raw:-0}"
}

# Extract duration from result event (ms)
extract_duration_ms() {
  local file="$1"

  [[ -s "$file" ]] || { echo "0"; return; }

  jq -r 'select(.type == "result") | .duration_ms // 0' "$file" 2>/dev/null | tail -1 || echo "0"
}
