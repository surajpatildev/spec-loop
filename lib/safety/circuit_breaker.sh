#!/usr/bin/env bash
# spec-loop circuit breaker — stagnation detection
#
# State machine: CLOSED → OPEN → HALF_OPEN
#   CLOSED:    Normal operation. Tracking consecutive no-progress iterations.
#   OPEN:      Halted. Too many iterations without progress. Cooldown timer active.
#   HALF_OPEN: After cooldown, allow one iteration to test.

CB_STATE_FILE=""
CB_STATE="CLOSED"
CB_FAILURES=0
CB_LAST_COMMIT=""
CB_OPENED_AT=""

cb_init() {
  CB_STATE_FILE="${SESSION_DIR}/.circuit_breaker.json"

  if [[ -f "$CB_STATE_FILE" ]]; then
    CB_STATE=$(jq -r '.state // "CLOSED"' "$CB_STATE_FILE")
    CB_FAILURES=$(jq -r '.failures // 0' "$CB_STATE_FILE")
    CB_LAST_COMMIT=$(jq -r '.last_commit // ""' "$CB_STATE_FILE")
    CB_OPENED_AT=$(jq -r '.opened_at // ""' "$CB_STATE_FILE")
  fi

  # Initialize CB_LAST_COMMIT to current HEAD if not set
  if [[ -z "$CB_LAST_COMMIT" ]]; then
    CB_LAST_COMMIT=$(get_head_sha)
  fi
}

cb_save() {
  [[ -n "$CB_STATE_FILE" ]] || return

  cat > "$CB_STATE_FILE" <<EOF
{
  "state": "$CB_STATE",
  "failures": $CB_FAILURES,
  "last_commit": "$CB_LAST_COMMIT",
  "opened_at": "$CB_OPENED_AT"
}
EOF
}

# Call before each iteration. Returns 0 if OK to proceed, 1 if circuit is open.
cb_check() {
  case "$CB_STATE" in
    CLOSED)
      return 0
      ;;
    OPEN)
      # Check cooldown
      if [[ -n "$CB_OPENED_AT" ]]; then
        local now elapsed
        now=$(date +%s)
        local opened
        opened=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CB_OPENED_AT" +%s 2>/dev/null || date -d "$CB_OPENED_AT" +%s 2>/dev/null || echo "0")
        elapsed=$(( (now - opened) / 60 ))

        if [[ "$elapsed" -ge "$CB_COOLDOWN_MINUTES" ]]; then
          CB_STATE="HALF_OPEN"
          cb_save
          step_warn "Circuit breaker: HALF_OPEN (cooldown elapsed, allowing one attempt)"
          return 0
        fi

        local remaining=$(( CB_COOLDOWN_MINUTES - elapsed ))
        step_error "Circuit breaker: OPEN (${remaining}m cooldown remaining)"
        return 1
      fi

      # CB_OPENED_AT is empty — shouldn't happen, but recover gracefully
      step_error "Circuit breaker: OPEN (no timestamp, resetting)"
      CB_STATE="CLOSED"
      CB_FAILURES=0
      cb_save
      return 0
      ;;
    HALF_OPEN)
      return 0
      ;;
  esac
}

# Call after each iteration with progress indicator.
# IMPORTANT: Call this from the parent shell, NOT inside $() subshell,
# otherwise the state updates (CB_LAST_COMMIT, CB_FAILURES, etc.) are lost.
cb_record() {
  local made_progress="$1"  # "true" or "false"

  if [[ "$made_progress" == "true" ]]; then
    CB_FAILURES=0
    CB_STATE="CLOSED"
    # Update last known commit
    CB_LAST_COMMIT=$(get_head_sha)
  else
    CB_FAILURES=$((CB_FAILURES + 1))

    if [[ "$CB_FAILURES" -ge "$CB_NO_PROGRESS_THRESHOLD" ]]; then
      CB_STATE="OPEN"
      CB_OPENED_AT=$(timestamp_iso)
      step_error "Circuit breaker: OPEN after ${CB_FAILURES} iterations without progress"
    fi
  fi

  cb_save
}
