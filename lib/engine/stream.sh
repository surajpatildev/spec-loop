#!/usr/bin/env bash
# spec-loop stream-json event processor — real-time Claude Code output display

# Track tool call count for summary
_STREAM_TOOL_COUNT=0
_STREAM_START_EPOCH=0

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
    step_info "session  ${C_DIM}model=${model}  id=${session:0:8}${C_RESET}"
    _STREAM_TOOL_COUNT=0
    _STREAM_START_EPOCH=$(date +%s)
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
      local tool_name tool_cmd
      tool_name=$(jq -r '.message.content[0].name // "tool"' <<<"$line")

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

      # Format: → Read     AGENTS.md
      local padded_name
      padded_name=$(printf '%-8s' "$tool_name")
      if [[ -n "$tool_cmd" ]]; then
        step_info "${C_DIM}${padded_name}${C_RESET} $tool_cmd"
      else
        step_info "${C_DIM}${padded_name}${C_RESET}"
      fi
      ;;
    text)
      if [[ "$VERBOSE" == "true" ]]; then
        local text
        text=$(jq -r '.message.content[0].text // ""' <<<"$line")
        text=$(trim_single_line "$text" 100)
        [[ -n "$text" ]] && step_info "text: $text"
      fi
      ;;
    thinking)
      # Always show a subtle thinking indicator (not just verbose)
      step_info "${C_DIM}thinking…${C_RESET}"
      ;;
  esac
}

_handle_user_event() {
  local line="$1"
  local content_type
  content_type=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].type // "") else "" end' <<<"$line")

  if [[ "$content_type" == "tool_result" ]]; then
    local is_error
    is_error=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].is_error // false) else false end' <<<"$line")

    if [[ "$is_error" == "true" ]]; then
      local err_content
      err_content=$(jq -r 'if (.message.content | type) == "array" then (.message.content[0].content // "") else "" end' <<<"$line")
      err_content=$(trim_single_line "$err_content" 80)
      step_warn "error: ${err_content}"
    elif [[ "$VERBOSE" == "true" ]]; then
      local stdout
      stdout=$(jq -r 'if (.tool_use_result | type) == "object" then (.tool_use_result.stdout // "") else "" end' <<<"$line")
      stdout=$(trim_single_line "$stdout" 90)
      [[ -n "$stdout" ]] && step_ok "result: $stdout"
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
        step_warn "rate-limit: ${rl_status} ${C_DIM}(resets in ${dur_str})${C_RESET}"
      else
        step_warn "rate-limit: ${rl_status}"
      fi
    else
      step_warn "rate-limit: ${rl_status}"
    fi
  fi
}

_handle_result_event() {
  local line="$1"
  local subtype duration cost
  subtype=$(jq -r '.subtype // "unknown"' <<<"$line")
  duration=$(jq -r '.duration_ms // 0' <<<"$line")
  cost=$(jq -r '.total_cost_usd // 0' <<<"$line")

  # Convert duration to human-readable
  local duration_s
  duration_s=$(( duration / 1000 ))
  local dur_str
  dur_str=$(format_duration "$duration_s")

  local cost_str
  cost_str=$(format_cost "$cost")

  step_ok "result   ${C_DIM}${dur_str} ${SYM_DIAMOND} ${cost_str} ${SYM_DIAMOND} ${_STREAM_TOOL_COUNT} tools${C_RESET}"
}
