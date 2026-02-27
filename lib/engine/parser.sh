#!/usr/bin/env bash
# spec-loop output parser — extract status, tags, and metrics from Claude output

# Extract text content from stream-json output
# Prefers the "result" event (.result field) which has the complete response.
# Falls back to assistant text events if no result event exists.
extract_parseable_text() {
  local file="$1"

  [[ -s "$file" ]] || return

  if command -v jq >/dev/null 2>&1; then
    # First try: extract from the result event (authoritative, non-duplicated)
    local result_text
    result_text=$(jq -rs '[ .[] | select(.type == "result") | .result ] | last // empty' "$file" 2>/dev/null)

    if [[ -n "$result_text" ]]; then
      printf '%s\n' "$result_text"
      return
    fi

    # Second try: concatenate assistant text events (streaming fallback)
    local assistant_text
    assistant_text=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text // empty' "$file" 2>/dev/null || true)

    if [[ -n "$assistant_text" ]]; then
      printf '%s\n' "$assistant_text"
      return
    fi
  fi

  # Fallback: treat as plain text
  cat "$file"
}

# Parse a key-value line from output: "KEY: value"
# Searches for KEY: anywhere in the line (handles leading whitespace, backticks, etc.)
parse_kv_value() {
  local key="$1"
  local file="$2"

  [[ -s "$file" ]] || { echo ""; return; }

  # First try: exact match at line start (fastest, most precise)
  local result
  result=$(extract_parseable_text "$file" | awk -v prefix="$key: " 'index($0, prefix) == 1 && !found { value = substr($0, length(prefix) + 1); found=1 } END { print value }')

  if [[ -n "$result" ]]; then
    echo "$result"
    return
  fi

  # Fallback: find KEY: anywhere in the line (handles whitespace, code blocks, etc.)
  result=$(extract_parseable_text "$file" | grep -o "${key}: [A-Z_0-9]*" | head -1 | sed "s/^${key}: //")
  echo "${result:-}"
}

# Check if output contains a <promise>TAG</promise>
output_has_tag() {
  local file="$1"
  local tag="$2"

  [[ -s "$file" ]] || return 1

  # Search for the tag anywhere in the line (handles whitespace/backticks)
  extract_parseable_text "$file" | grep -q "<promise>${tag}</promise>"
}

# Extract cost from result event
extract_cost() {
  local file="$1"

  [[ -s "$file" ]] || { echo "0"; return; }

  local raw
  raw=$(jq -r 'select(.type == "result") | .total_cost_usd // 0' "$file" 2>/dev/null | tail -1)
  if [[ "$raw" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "$raw"
  else
    echo "0"
  fi
}

# Extract duration from result event (ms)
extract_duration_ms() {
  local file="$1"

  [[ -s "$file" ]] || { echo "0"; return; }

  local raw
  raw=$(jq -r 'select(.type == "result") | .duration_ms // 0' "$file" 2>/dev/null | tail -1)
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "0"
  fi
}

extract_claude_session_id() {
  local file="$1"

  [[ -s "$file" ]] || { echo ""; return; }

  jq -r 'select(.type == "system" and .subtype == "init") | .session_id // empty' "$file" 2>/dev/null | tail -1 || true
}
