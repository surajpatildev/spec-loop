#!/usr/bin/env bash
# spec-loop stream-json event processor — real-time Claude Code output display

# Track tool call count for summary
_STREAM_TOOL_COUNT=0
_STREAM_START_EPOCH=0

# Track the last Bash tool_use_id for grouping results
_STREAM_LAST_BASH_ID=""
_STREAM_LAST_BASH_CMD=""

# Phase elapsed time — tracked as epoch, shown on tool lines and result
_PHASE_START_EPOCH=0
_PHASE_LABEL=""

# Inline spinner — runs between stream events
_STREAM_SPINNER_PID=""

_phase_timer_start() {
  _PHASE_START_EPOCH=$(date +%s)
}

_phase_timer_stop() {
  _stream_spinner_stop
  _PHASE_START_EPOCH=0
  _PHASE_LABEL=""
}

# Get elapsed seconds since phase started
_phase_elapsed() {
  if [[ "$_PHASE_START_EPOCH" -gt 0 ]]; then
    local now
    now=$(date +%s)
    echo $(( now - _PHASE_START_EPOCH ))
  else
    echo 0
  fi
}

# Start a braille spinner on the current line (between events)
_stream_spinner_start() {
  [[ "$TERM_IS_INTERACTIVE" == "true" ]] || return 0
  _stream_spinner_stop

  local label="${1:-}"
  local start_epoch="$_PHASE_START_EPOCH"
  (
    local i=0
    local frame_count=${#SPINNER_FRAMES[@]}
    while true; do
      local frame="${SPINNER_FRAMES[$((i % frame_count))]}"
      local elapsed=""
      if [[ "$start_epoch" -gt 0 ]]; then
        local now
        now=$(date +%s)
        elapsed=" ${C_DIM}[$(( now - start_epoch ))s]${C_RESET}"
      fi
      printf '\r      %b%s%b %b%s%b%b ' "$C_BLUE" "$frame" "$C_RESET" "$C_DIM" "$label" "$C_RESET" "$elapsed"
      sleep 0.1
      i=$((i + 1))
    done
  ) &
  _STREAM_SPINNER_PID=$!
  disown "$_STREAM_SPINNER_PID" 2>/dev/null || true
}

# Stop spinner and clear its line
_stream_spinner_stop() {
  if [[ -n "$_STREAM_SPINNER_PID" ]]; then
    kill "$_STREAM_SPINNER_PID" 2>/dev/null || true
    wait "$_STREAM_SPINNER_PID" 2>/dev/null 3>/dev/null || true
    _STREAM_SPINNER_PID=""
    term_clear_line
  fi
}

# Stream output helpers — stop spinner, print, restart spinner
# These wrap the logging functions so the spinner doesn't collide
_sinfo() {
  _stream_spinner_stop
  step_info "$1"
  _stream_spinner_start "$_PHASE_LABEL"
}

_sok() {
  _stream_spinner_stop
  step_ok "$1"
  _stream_spinner_start "$_PHASE_LABEL"
}

_swarn() {
  _stream_spinner_stop
  step_warn "$1"
  _stream_spinner_start "$_PHASE_LABEL"
}

process_stream_event() {
  local line="$1"

  # Skip empty lines
  [[ -n "$line" ]] || return

  # Validate JSON
  if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
    if [[ "$VERBOSE" == "true" ]]; then
      local raw
      raw=$(trim_single_line "$line" 100)
      [[ -n "$raw" ]] && step_warn "non-json: $raw"
    fi
    return
  fi

  local event_type
  event_type=$(jq -r '.type // ""' <<<"$line")

  case "$event_type" in
    system)
      _handle_system_event "$line"
      ;;
    assistant)
      _handle_assistant_event "$line"
      ;;
    user)
      _handle_user_event "$line"
      ;;
    rate_limit_event)
      _handle_rate_limit_event "$line"
      ;;
    result)
      _handle_result_event "$line"
      _phase_timer_stop
      ;;
  esac
}

_handle_system_event() {
  local line="$1"
  local subtype
  subtype=$(jq -r '.subtype // ""' <<<"$line")

  if [[ "$subtype" == "init" ]]; then
    local model session
    model=$(jq -r '.model // "unknown"' <<<"$line")
    session=$(jq -r '.session_id // "unknown"' <<<"$line")
    _sinfo "session  ${C_DIM}model=${model}  id=${session:0:8}${C_RESET}"
    _STREAM_TOOL_COUNT=0
    _STREAM_START_EPOCH=$(date +%s)
    _STREAM_LAST_BASH_ID=""
    _STREAM_LAST_BASH_CMD=""
  fi
}

# Tools to hide from default display (internal/noise)
_is_internal_tool() {
  local name="$1"
  case "$name" in
    TodoWrite|TodoRead|AskUserQuestion|EnterPlanMode|ExitPlanMode|EnterWorktree)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Strip project root from file paths for compact display
_relative_path() {
  local path="$1"
  local cwd
  cwd=$(pwd)
  # Strip the cwd prefix if present
  if [[ "$path" == "$cwd/"* ]]; then
    echo "${path#$cwd/}"
  elif [[ "$path" == /Users/*/projects/* ]]; then
    # Strip up to the project name for absolute paths
    echo "${path#/Users/*/projects/*/}"
  else
    echo "$path"
  fi
}

_handle_assistant_event() {
  local line="$1"
  local content_type
  content_type=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].type // "") else "" end' <<<"$line")

  case "$content_type" in
    tool_use)
      local tool_name tool_cmd tool_id
      tool_name=$(jq -r '.message.content[0].name // "tool"' <<<"$line")
      tool_id=$(jq -r '.message.content[0].id // ""' <<<"$line")

      # Skip internal tools unless verbose
      if _is_internal_tool "$tool_name" && [[ "$VERBOSE" != "true" ]]; then
        return
      fi

      tool_cmd=$(jq -r '.message.content[0].input.command // .message.content[0].input.file_path // .message.content[0].input.pattern // ""' <<<"$line")

      # Make paths relative for compact display
      if [[ -n "$tool_cmd" ]]; then
        tool_cmd=$(_relative_path "$tool_cmd")
        tool_cmd=$(trim_single_line "$tool_cmd" 70)
      fi

      _STREAM_TOOL_COUNT=$((_STREAM_TOOL_COUNT + 1))

      # Track Bash tool calls for result grouping
      if [[ "$tool_name" == "Bash" ]]; then
        _STREAM_LAST_BASH_ID="$tool_id"
        _STREAM_LAST_BASH_CMD="$tool_cmd"
      else
        _STREAM_LAST_BASH_ID=""
        _STREAM_LAST_BASH_CMD=""
      fi

      # Format: → Read     AGENTS.md
      local padded_name
      padded_name=$(printf '%-8s' "$tool_name")
      if [[ -n "$tool_cmd" ]]; then
        _sinfo "${C_DIM}${padded_name}${C_RESET} $tool_cmd"
      else
        _sinfo "${C_DIM}${padded_name}${C_RESET}"
      fi
      ;;
    text)
      if [[ "$VERBOSE" == "true" ]]; then
        local text
        text=$(jq -r '.message.content[0].text // ""' <<<"$line")
        text=$(trim_single_line "$text" 100)
        [[ -n "$text" ]] && _sinfo "text: $text"
      fi
      ;;
    thinking)
      # Always show a subtle thinking indicator (not just verbose)
      _sinfo "${C_DIM}thinking…${C_RESET}"
      ;;
  esac
}

_handle_user_event() {
  local line="$1"
  local content_type
  content_type=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].type // "") else "" end' <<<"$line")

  if [[ "$content_type" == "tool_result" ]]; then
    local is_error tool_use_id
    is_error=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].is_error // false) else false end' <<<"$line")
    tool_use_id=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].tool_use_id // "") else "" end' <<<"$line")

    if [[ "$is_error" == "true" ]]; then
      local err_content
      err_content=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].content // "") else "" end' <<<"$line")
      err_content=$(trim_single_line "$err_content" 80)
      _swarn "error: ${err_content}"
      _STREAM_LAST_BASH_ID=""
    elif [[ -n "$_STREAM_LAST_BASH_ID" && "$tool_use_id" == "$_STREAM_LAST_BASH_ID" ]]; then
      # This is the result of the last Bash command — show pass/fail
      local result_content
      result_content=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].content // "") else "" end' <<<"$line")
      local result_summary
      result_summary=$(trim_single_line "$result_content" 80)
      if [[ -n "$result_summary" ]]; then
        _sok "${C_DIM}${result_summary}${C_RESET}"
      else
        _sok "${C_DIM}done${C_RESET}"
      fi
      _STREAM_LAST_BASH_ID=""
    elif [[ "$VERBOSE" == "true" ]]; then
      local stdout
      stdout=$(jq -r 'if (.tool_use_result | type) == "object" then (.tool_use_result.stdout // "") else "" end' <<<"$line")
      stdout=$(trim_single_line "$stdout" 90)
      [[ -n "$stdout" ]] && _sok "result: $stdout"
    fi
  fi
}

_handle_rate_limit_event() {
  local line="$1"
  local rl_status
  rl_status=$(jq -r '.rate_limit_info.status // "unknown"' <<<"$line")

  # Only show rate limit warnings when NOT allowed (suppress noise)
  if [[ "$rl_status" != "allowed" ]]; then
    local resets_at
    resets_at=$(jq -r '.rate_limit_info.resetsAt // ""' <<<"$line")
    if [[ -n "$resets_at" && "$resets_at" != "null" ]]; then
      local now reset_in
      now=$(date +%s)
      reset_in=$((resets_at - now))
      if [[ "$reset_in" -gt 0 ]]; then
        local dur_str
        dur_str=$(format_duration "$reset_in")
        _swarn "rate-limit: ${rl_status} ${C_DIM}(resets in ${dur_str})${C_RESET}"
      else
        _swarn "rate-limit: ${rl_status}"
      fi
    else
      _swarn "rate-limit: ${rl_status}"
    fi
  fi
}

_handle_result_event() {
  local line="$1"
  local cost
  cost=$(jq -r '.total_cost_usd // 0' <<<"$line")

  # Use wall-clock elapsed from phase timer
  local elapsed
  elapsed=$(_phase_elapsed)
  local dur_str
  dur_str=$(format_duration "$elapsed")

  local cost_str
  cost_str=$(format_cost "$cost")

  # Stop spinner permanently (last event — don't restart)
  _stream_spinner_stop
  step_ok "result   ${C_DIM}${dur_str} ${SYM_DIAMOND} ${cost_str} ${SYM_DIAMOND} ${_STREAM_TOOL_COUNT} tools${C_RESET}"
}
