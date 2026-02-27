#!/usr/bin/env bash
# spec-loop utility functions

trim_single_line() {
  local input="$1"
  local max_len="${2:-120}"
  local trimmed
  trimmed=$(printf '%s' "$input" | tr '\n' ' ' | tr -s ' ')
  if [[ ${#trimmed} -gt $max_len ]]; then
    printf '%s…' "${trimmed:0:$max_len}"
  else
    printf '%s' "$trimmed"
  fi
}

int_or_zero() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "0"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_positive_int() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name must be a positive integer (got: $value)"
}

require_non_negative_int() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer (got: $value)"
}

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

get_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

get_current_branch() {
  git branch --show-current 2>/dev/null || echo "unknown"
}

get_head_sha() {
  git rev-parse --verify HEAD 2>/dev/null || echo ""
}

timestamp() {
  date '+%Y%m%d_%H%M%S'
}

timestamp_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

timestamp_human() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Duration formatting: seconds → human-readable
format_duration() {
  local seconds="$1"
  if [[ "$seconds" -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ "$seconds" -lt 3600 ]]; then
    local m=$((seconds / 60))
    local s=$((seconds % 60))
    echo "${m}m ${s}s"
  else
    local h=$((seconds / 3600))
    local m=$(( (seconds % 3600) / 60 ))
    echo "${h}h ${m}m"
  fi
}

# Format cost: 0.123456 → $0.12
format_cost() {
  local cost="$1"
  printf '$%.2f' "$cost"
}
