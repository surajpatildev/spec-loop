#!/usr/bin/env bash
# spec-loop session management — resume support

SESSION_STATE_FILE=""

session_init() {
  SESSION_STATE_FILE="${SESSION_DIR}/.session_state.json"
}

# Save resume state
session_save_state() {
  local spec_dir="$1"
  local loop_index="$2"
  local session_path="$3"

  [[ -n "$SESSION_STATE_FILE" ]] || return

  cat > "$SESSION_STATE_FILE" <<EOF
{
  "spec_dir": "$spec_dir",
  "loop_index": $loop_index,
  "session_path": "$session_path",
  "saved_at": "$(timestamp_iso)"
}
EOF
}

# Load resume state. Returns 0 if state exists, 1 otherwise.
session_load_state() {
  [[ -f "$SESSION_STATE_FILE" ]] || return 1

  RESUME_SPEC_DIR=$(jq -r '.spec_dir // ""' "$SESSION_STATE_FILE")
  RESUME_LOOP_INDEX=$(jq -r '.loop_index // 1' "$SESSION_STATE_FILE")
  RESUME_SESSION_PATH=$(jq -r '.session_path // ""' "$SESSION_STATE_FILE")

  [[ -n "$RESUME_SPEC_DIR" && -d "$RESUME_SPEC_DIR" ]]
}

# Clear resume state after completion
session_clear_state() {
  [[ -f "$SESSION_STATE_FILE" ]] && rm -f "$SESSION_STATE_FILE"
}

# Get the most recent session directory
session_latest() {
  local latest
  latest=$(find "$SESSION_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | head -1)
  echo "$latest"
}
