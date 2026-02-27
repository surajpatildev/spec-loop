#!/usr/bin/env bash
# spec-loop preflight checks — validate environment before run

preflight() {
  # Claude Code binary
  require_cmd "$CLAUDE_BIN"

  # jq for JSON parsing, bc for cost arithmetic
  require_cmd "jq"
  require_cmd "bc"

  # Git repo check
  is_git_repo || die "Not inside a git repository. Run 'git init' first."

  # Config file
  if [[ ! -f "$SPECLOOPRC" ]]; then
    die "No .speclooprc found. Run 'spec-loop init' first."
  fi

  # Validate numeric config
  require_positive_int "MAX_LOOPS" "$MAX_LOOPS"
  require_positive_int "MAX_REVIEW_FIX_LOOPS" "$MAX_REVIEW_FIX_LOOPS"
  require_non_negative_int "MAX_TASKS_PER_RUN" "$MAX_TASKS_PER_RUN"

  # Session directory
  mkdir -p "$SESSION_DIR"

  # Specs directory
  if [[ ! -d "$SPECS_DIR" ]]; then
    die "Specs directory not found: $SPECS_DIR\n  Run 'spec-loop init' or create it manually."
  fi
}
