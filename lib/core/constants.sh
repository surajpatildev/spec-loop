#!/usr/bin/env bash
# spec-loop constants

SPECLOOP_VERSION="0.1.0"

# ── Exit codes ──────────────────────────────────────
EXIT_OK=0
EXIT_MAX_ITERATIONS=1
EXIT_BLOCKED=2
EXIT_CIRCUIT_OPEN=3
EXIT_ERROR=4

# ── Defaults ────────────────────────────────────────
DEFAULT_MAX_LOOPS=25
DEFAULT_MAX_REVIEW_FIX_LOOPS=3
DEFAULT_MAX_TASKS_PER_RUN=0
DEFAULT_CLAUDE_BIN="claude"
DEFAULT_SPECS_DIR=".agents/specs"
DEFAULT_SESSION_DIR=".spec-loop/sessions"
DEFAULT_CB_NO_PROGRESS_THRESHOLD=3
DEFAULT_CB_COOLDOWN_MINUTES=30
DEFAULT_PREVIEW_LINES=5

# ── Promise tags ────────────────────────────────────
PROMISE_COMPLETE="COMPLETE"
PROMISE_BLOCKED="BLOCKED"

# ── Status keys ─────────────────────────────────────
BUILD_STATUS_KEY="BUILD_STATUS"
REVIEW_STATUS_KEY="REVIEW_STATUS"

# ── Colors ──────────────────────────────────────────
_setup_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED='\033[0;31m'
    C_RED_BOLD='\033[1;31m'
    C_GREEN='\033[0;32m'
    C_GREEN_BOLD='\033[1;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_GRAY='\033[0;37m'
    C_DIM='\033[2m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
  else
    C_RED='' C_RED_BOLD='' C_GREEN='' C_GREEN_BOLD=''
    C_YELLOW='' C_BLUE='' C_CYAN='' C_GRAY=''
    C_DIM='' C_BOLD='' C_RESET=''
  fi
}

# ── Symbols ─────────────────────────────────────────
_setup_symbols() {
  local locale_val="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if [[ "$locale_val" == *UTF-8* || "$locale_val" == *utf8* ]]; then
    SYM_OK="✓"
    SYM_FAIL="✗"
    SYM_WARN="⚠"
    SYM_PHASE="●"
    SYM_ARROW="→"
    SYM_DIAMOND="◆"
    SYM_BOX_TL="╭"
    SYM_BOX_TR="╮"
    SYM_BOX_BL="╰"
    SYM_BOX_BR="╯"
    SYM_BOX_H="─"
    SYM_BOX_V="│"
    SYM_BAR_FULL="█"
    SYM_BAR_EMPTY="░"
    SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  else
    SYM_OK="[OK]"
    SYM_FAIL="[FAIL]"
    SYM_WARN="[WARN]"
    SYM_PHASE="*"
    SYM_ARROW="->"
    SYM_DIAMOND="+"
    SYM_BOX_TL="+"
    SYM_BOX_TR="+"
    SYM_BOX_BL="+"
    SYM_BOX_BR="+"
    SYM_BOX_H="-"
    SYM_BOX_V="|"
    SYM_BAR_FULL="#"
    SYM_BAR_EMPTY="."
    SPINNER_FRAMES=('|' '/' '-' '\')
  fi
}

_setup_colors
_setup_symbols
