#!/usr/bin/env bash
# spec-loop logging — charm.sh-inspired terminal output

# ── Core log ────────────────────────────────────────

log() {
  local level="$1"; shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

die() {
  echo -e "  ${C_RED_BOLD}${SYM_FAIL}${C_RESET} $*" >&2
  exit "${EXIT_ERROR:-4}"
}

# ── Decorative ──────────────────────────────────────

# Draw a rounded box with a title label
#   box_header "Spec" 50
box_header() {
  local label="$1"
  local width="${2:-52}"
  local inner=$((width - 2))
  local label_line="${SYM_BOX_H} ${label} "
  local remaining=$((inner - ${#label} - 3))
  local pad
  pad=$(printf "%${remaining}s" | tr ' ' "${SYM_BOX_H}")

  echo ""
  echo -e "  ${C_CYAN}${SYM_BOX_TL}${label_line}${pad}${SYM_BOX_TR}${C_RESET}"
}

# Box content line — handles ANSI color codes for proper alignment
#   box_line "  user-auth" 50
box_line() {
  local content="$1"
  local width="${2:-52}"
  local inner=$((width - 2))

  # Strip ANSI escape codes to calculate visible width
  local stripped
  stripped=$(printf '%b' "$content" | sed $'s/\033\\[[0-9;]*m//g')
  local visible_len=${#stripped}
  local pad_needed=$((inner - visible_len))

  if [[ "$pad_needed" -gt 0 ]]; then
    local padding
    padding=$(printf "%${pad_needed}s" "")
    echo -e "  ${C_CYAN}${SYM_BOX_V}${C_RESET}${content}${padding}${C_CYAN}${SYM_BOX_V}${C_RESET}"
  else
    echo -e "  ${C_CYAN}${SYM_BOX_V}${C_RESET}${content}${C_CYAN}${SYM_BOX_V}${C_RESET}"
  fi
}

# Box footer
#   box_footer 50
box_footer() {
  local width="${1:-52}"
  local inner=$((width - 2))
  local line
  line=$(printf "%${inner}s" | tr ' ' "${SYM_BOX_H}")
  echo -e "  ${C_CYAN}${SYM_BOX_BL}${line}${SYM_BOX_BR}${C_RESET}"
}

# Empty box line (padding)
box_empty() {
  local width="${1:-52}"
  local inner=$((width - 2))
  local spaces
  spaces=$(printf "%${inner}s" "")
  echo -e "  ${C_CYAN}${SYM_BOX_V}${C_RESET}${spaces}${C_CYAN}${SYM_BOX_V}${C_RESET}"
}

# Section separator (no box)
#   separator "Iteration 1 of 25"
separator() {
  local label="$1"
  local width="${2:-52}"
  local label_part="${SYM_BOX_H}${SYM_BOX_H} ${label} "
  local remaining=$((width - ${#label} - 5))
  local pad
  pad=$(printf "%${remaining}s" | tr ' ' "${SYM_BOX_H}")
  echo ""
  echo -e "  ${C_DIM}${label_part}${pad}${C_RESET}"
}

# ── Progress bar ────────────────────────────────────

# progress_bar 3 7  →  "████████░░░░░░░░ 3/7 done"
progress_bar() {
  local current="$1"
  local total="$2"
  local bar_width="${3:-16}"
  local label="${4:-done}"

  if [[ "$total" -eq 0 ]]; then
    echo "0/0 ${label}"
    return
  fi

  local filled=$((bar_width * current / total))
  local empty=$((bar_width - filled))
  local bar=""

  local i
  for ((i = 0; i < filled; i++)); do
    bar+="${SYM_BAR_FULL}"
  done
  for ((i = 0; i < empty; i++)); do
    bar+="${SYM_BAR_EMPTY}"
  done

  echo -e "${C_GREEN}${bar}${C_RESET} ${current}/${total} ${label}"
}

# ── Phase output ────────────────────────────────────

# Phase start: ● build [0s]
phase() {
  local label="$1"
  # Stop any existing phase timer before printing
  if declare -F _phase_timer_stop >/dev/null 2>&1; then
    _phase_timer_stop
  fi
  echo ""
  echo -e "  ${C_BLUE}${SYM_PHASE}${C_RESET} ${C_BOLD}${label}${C_RESET}"
  # Start elapsed timer for this phase
  if declare -F _phase_timer_start >/dev/null 2>&1; then
    _phase_timer_start "$label"
  fi
}

# Info line: → tool Bash: npm run lint
step_info() {
  local message="$1"
  echo -e "      ${C_BLUE}${SYM_ARROW}${C_RESET} ${message}"
}

# Success line: ✓ result 0 errors
step_ok() {
  local message="$1"
  echo -e "      ${C_GREEN}${SYM_OK}${C_RESET} ${message}"
}

# Warning line: ⚠ FAIL 2 must-fix
step_warn() {
  local message="$1"
  echo -e "      ${C_YELLOW}${SYM_WARN}${C_RESET} ${message}"
}

# Error line: ✗ build failed
step_error() {
  local message="$1"
  echo -e "      ${C_RED}${SYM_FAIL}${C_RESET} ${message}"
}

# Task completion line
task_complete() {
  local task_name="$1"
  local remaining="$2"
  echo ""
  echo -e "  ${C_GREEN}${SYM_OK}${C_RESET} ${C_BOLD}${task_name}${C_RESET} ${C_DIM}${SYM_ARROW} ${remaining} remaining${C_RESET}"
}

# ── Header ──────────────────────────────────────────

print_header() {
  echo ""
  echo -e "  ${C_BOLD}spec-loop${C_RESET} ${C_DIM}v${SPECLOOP_VERSION}${C_RESET}"
}
