#!/usr/bin/env bash
# spec-loop rate limiter — pause when rate limit events detected

RL_CONSECUTIVE_HITS=0
RL_MAX_CONSECUTIVE=3
RL_BACKOFF_SECONDS=30

# Handle a rate limit event from stream-json
rl_on_rate_limit() {
  local status="$1"  # "rate_limited" or other

  if [[ "$status" == "rate_limited" ]]; then
    RL_CONSECUTIVE_HITS=$((RL_CONSECUTIVE_HITS + 1))

    if [[ "$RL_CONSECUTIVE_HITS" -ge "$RL_MAX_CONSECUTIVE" ]]; then
      local wait_secs=$((RL_BACKOFF_SECONDS * RL_CONSECUTIVE_HITS))
      step_warn "Rate limited ${RL_CONSECUTIVE_HITS} times. Backing off ${wait_secs}s..."
      _rl_countdown "$wait_secs"
      RL_CONSECUTIVE_HITS=0
    fi
  else
    # Reset on non-limited status
    RL_CONSECUTIVE_HITS=0
  fi
}

# Countdown display
_rl_countdown() {
  local seconds="$1"
  local i
  for ((i = seconds; i > 0; i--)); do
    printf "\r      ${C_YELLOW}${SYM_WARN}${C_RESET} Rate limit cooldown: %ds  " "$i"
    sleep 1
  done
  printf "\r      ${C_GREEN}${SYM_OK}${C_RESET} Resuming...                \n"
}
