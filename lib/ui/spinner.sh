#!/usr/bin/env bash
# spec-loop spinner — braille dot animation during Claude Code execution

SPINNER_PID=""
_SPINNER_PREV_TRAP=""

spinner_start() {
  local label="${1:-working}"

  # Only in interactive terminals
  [[ "$TERM_IS_INTERACTIVE" == "true" ]] || return

  # Stop any existing spinner first (prevent orphaned processes)
  if [[ -n "$SPINNER_PID" ]]; then
    spinner_stop
  fi

  term_cursor_hide

  (
    local i=0
    local frame_count=${#SPINNER_FRAMES[@]}
    while true; do
      local frame="${SPINNER_FRAMES[$((i % frame_count))]}"
      printf '\r      %b%s%b %s  ' "$C_BLUE" "$frame" "$C_RESET" "$label"
      sleep 0.1
      i=$((i + 1))
    done
  ) &
  SPINNER_PID=$!

  # Chain onto existing EXIT trap instead of overwriting
  _SPINNER_PREV_TRAP=$(trap -p EXIT | sed "s/^trap -- '\\(.*\\)' EXIT$/\\1/" || true)
  trap 'spinner_stop; eval "$_SPINNER_PREV_TRAP"' EXIT
  trap 'spinner_stop; exit 130' INT
}

spinner_stop() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    term_clear_line
    term_cursor_show
  fi
}

# Update spinner label without restart
spinner_update() {
  local label="$1"

  if [[ -n "$SPINNER_PID" ]]; then
    spinner_stop
    spinner_start "$label"
  fi
}
