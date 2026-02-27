#!/usr/bin/env bash
# spec-loop streaming preview — real-time output during Claude Code execution

# Preview buffer for streaming output
PREVIEW_BUFFER=""
PREVIEW_LINE_COUNT=0

preview_reset() {
  PREVIEW_BUFFER=""
  PREVIEW_LINE_COUNT=0
}

# Add a line to the streaming preview (shown below the spinner)
preview_add_line() {
  local line="$1"
  local max_lines="${PREVIEW_LINES:-5}"

  [[ "$SHOW_PREVIEW" == "true" ]] || return
  [[ "$TERM_IS_INTERACTIVE" == "true" ]] || return

  # Trim line to terminal width
  local max_width=$((TERM_COLS - 10))
  if [[ ${#line} -gt $max_width ]]; then
    line="${line:0:$max_width}${SYM_ARROW}"
  fi

  PREVIEW_BUFFER+="      ${C_DIM}${line}${C_RESET}\n"
  PREVIEW_LINE_COUNT=$((PREVIEW_LINE_COUNT + 1))

  # Only keep last N lines
  if [[ "$PREVIEW_LINE_COUNT" -gt "$max_lines" ]]; then
    PREVIEW_BUFFER=$(echo -e "$PREVIEW_BUFFER" | tail -n "$max_lines")
    PREVIEW_LINE_COUNT=$max_lines
  fi
}

# Render the preview buffer (used with \r overwrite)
preview_render() {
  [[ "$SHOW_PREVIEW" == "true" ]] || return
  [[ -n "$PREVIEW_BUFFER" ]] || return

  echo -e "$PREVIEW_BUFFER"
}

# Clear preview from screen
preview_clear() {
  [[ "$SHOW_PREVIEW" == "true" ]] || return
  [[ "$PREVIEW_LINE_COUNT" -gt 0 ]] || return

  local i
  for ((i = 0; i < PREVIEW_LINE_COUNT; i++)); do
    term_move_up
    term_clear_line
  done

  preview_reset
}
