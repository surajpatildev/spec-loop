#!/usr/bin/env bash
# spec-loop stream-json event processor — real-time Claude Code output display

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
      local rl_status
      rl_status=$(jq -r '.rate_limit_info.status // "unknown"' <<<"$line")
      step_warn "rate-limit: $rl_status"
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
      tool_cmd=$(jq -r '.message.content[0].input.command // .message.content[0].input.file_path // ""' <<<"$line")
      tool_cmd=$(trim_single_line "$tool_cmd" 80)

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
      if [[ "$VERBOSE" == "true" ]]; then
        step_info "${C_DIM}thinking…${C_RESET}"
      fi
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
      step_warn "tool error"
    elif [[ "$VERBOSE" == "true" ]]; then
      local stdout
      stdout=$(jq -r 'if (.tool_use_result | type) == "object" then (.tool_use_result.stdout // "") else "" end' <<<"$line")
      stdout=$(trim_single_line "$stdout" 90)
      [[ -n "$stdout" ]] && step_ok "result: $stdout"
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

  step_ok "result   ${C_DIM}${dur_str} ${SYM_DIAMOND} ${cost_str}${C_RESET}"
}
