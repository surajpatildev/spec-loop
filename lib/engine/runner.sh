#!/usr/bin/env bash
# spec-loop Claude Code invocation wrapper
#
# CRITICAL: Each invocation creates a SEPARATE Claude session.
# We use --print mode (no session reuse) and redirect stderr separately
# to keep the stream-json output clean.
#
# The raw NDJSON is saved to a temp file. Callers extract what they need
# (cost, status, result text) via parser.sh helpers, then clean up.

# Run Claude and save raw NDJSON output to a file.
# Usage: run_claude <prompt_file> <ndjson_output_file>
run_claude() {
  local prompt_file="$1"
  local output_file="$2"

  local -a cmd=(
    "env" "-u" "CLAUDECODE"
    "$CLAUDE_BIN"
    "--dangerously-skip-permissions"
    "--print"
    "--output-format" "stream-json"
    "--verbose"
  )

  # Optional model override
  if [[ -n "$CLAUDE_MODEL" ]]; then
    cmd+=("--model" "$CLAUDE_MODEL")
  fi

  # Optional system prompt file (for injecting skill content)
  if [[ -n "${_SYSTEM_PROMPT_FILE:-}" ]]; then
    cmd+=("--append-system-prompt" "$(cat "$_SYSTEM_PROMPT_FILE")")
  fi

  # Extra user-provided args
  if [[ -n "$CLAUDE_EXTRA_ARGS" ]]; then
    local extra_args=()
    IFS=' ' read -ra extra_args <<< "$CLAUDE_EXTRA_ARGS"
    cmd+=("${extra_args[@]}")
  fi

  # Dry run mode
  if [[ "$DRY_RUN" == "true" ]]; then
    step_info "DRY RUN: ${cmd[*]} < $prompt_file"
    _dry_run_output "$prompt_file" "$output_file"
    return 0
  fi

  # CRITICAL: stderr goes to a separate file to prevent corruption of stream-json.
  # CRITICAL: PIPESTATUS must be read on the very next line after the pipeline.
  local stderr_file
  stderr_file=$(mktemp)

  set +e
  "${cmd[@]}" < "$prompt_file" 2>"$stderr_file" | tee "$output_file" | while IFS= read -r line; do
    process_stream_event "$line"
  done
  local status=${PIPESTATUS[0]}
  set -e

  # Show stderr if Claude failed
  if [[ "$status" -ne 0 && -s "$stderr_file" ]]; then
    step_error "Claude stderr:"
    head -5 "$stderr_file" | while IFS= read -r errline; do
      step_error "  $errline"
    done
  fi

  rm -f "$stderr_file" 2>/dev/null
  return "$status"
}

# Generate synthetic output for --dry-run mode
_dry_run_output() {
  local prompt_file="$1"
  local output_file="$2"

  if grep -q 'REVIEW_INSTRUCTIONS' "$prompt_file" 2>/dev/null; then
    cat > "$output_file" <<'EOF'
REVIEW_STATUS: PASS
MUST_FIX_COUNT: 0
SHOULD_FIX_COUNT: 0
SUGGESTION_COUNT: 0
EOF
  elif grep -q 'Fix all must-fix' "$prompt_file" 2>/dev/null; then
    cat > "$output_file" <<'EOF'
BUILD_STATUS: FIXES_APPLIED
EOF
  else
    cat > "$output_file" <<'EOF'
BUILD_STATUS: COMPLETED_TASK
EOF
  fi
}
