#!/usr/bin/env bash
# spec-loop terminal capability detection

TERM_COLS=80
TERM_HAS_UNICODE="false"
TERM_IS_INTERACTIVE="false"

detect_terminal() {
  # Column width
  if command -v tput >/dev/null 2>&1; then
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
  fi

  # Interactive check
  if [[ -t 1 ]]; then
    TERM_IS_INTERACTIVE="true"
  fi

  # Unicode check (already done in constants.sh via _setup_symbols)
  local locale_val="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if [[ "$locale_val" == *UTF-8* || "$locale_val" == *utf8* ]]; then
    TERM_HAS_UNICODE="true"
  fi
}

# Clear the current line (for spinner/progress updates)
term_clear_line() {
  if [[ "$TERM_IS_INTERACTIVE" == "true" ]]; then
    printf '\r'
    tput el 2>/dev/null || printf '\033[K'
  fi
}

# Move cursor up N lines
term_move_up() {
  local n="${1:-1}"
  if [[ "$TERM_IS_INTERACTIVE" == "true" ]]; then
    tput cuu "$n" 2>/dev/null || printf '\033[%dA' "$n"
  fi
}

# Hide cursor
term_cursor_hide() {
  [[ "$TERM_IS_INTERACTIVE" == "true" ]] && tput civis 2>/dev/null || true
}

# Show cursor
term_cursor_show() {
  [[ "$TERM_IS_INTERACTIVE" == "true" ]] && tput cnorm 2>/dev/null || true
}

detect_terminal
