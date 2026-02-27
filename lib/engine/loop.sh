#!/usr/bin/env bash
# spec-loop main orchestration — build → review → fix loop

cmd_run() {
  # Preflight
  preflight

  # Resolve spec
  local spec_dir
  spec_dir="$(resolve_spec_dir)"
  local spec_name
  spec_name="$(get_spec_name "$spec_dir")"

  # Safety systems
  cb_init
  session_init

  # Session setup — handle resume vs fresh
  local session_path loop_index

  if [[ "$RESUME" == "true" ]] && session_load_state; then
    spec_dir="$RESUME_SPEC_DIR"
    spec_name="$(get_spec_name "$spec_dir")"
    session_path="$RESUME_SESSION_PATH"
    loop_index="$RESUME_LOOP_INDEX"
    step_info "Resuming session for ${spec_name} at iteration ${loop_index}"
    # Reuse existing session directory
    mkdir -p "$session_path"
  else
    local session_ts
    session_ts="$(timestamp)"
    session_path="${SESSION_DIR}/${session_ts}"
    loop_index=1
    mkdir -p "$session_path"
    # Initialize session.json for new sessions
    _session_json_init "$session_path" "$spec_dir" "$spec_name"
  fi

  local total_tasks done_tasks pending_tasks
  total_tasks="$(count_total_tasks "$spec_dir")"
  done_tasks="$(count_done_tasks "$spec_dir")"
  pending_tasks="$(count_pending_tasks "$spec_dir")"

  # Header
  print_header

  local branch
  branch="$(get_current_branch)"

  box_header "Spec" 52
  box_empty
  box_line "  ${spec_name}"
  box_line "  $(progress_bar "$done_tasks" "$total_tasks" 16 "done") ${SYM_DIAMOND} ${pending_tasks} pending"
  box_line "  ${C_DIM}${branch}${C_RESET}"
  box_empty
  box_footer

  local total_cost=0
  local start_epoch
  start_epoch=$(date +%s)
  local iterations_completed=0

  while [[ "$loop_index" -le "$MAX_LOOPS" ]]; do
    # Circuit breaker check
    if ! cb_check; then
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "CIRCUIT_OPEN" "$iterations_completed"
      return "$EXIT_CIRCUIT_OPEN"
    fi

    # Save resume state
    session_save_state "$spec_dir" "$loop_index" "$session_path"

    pending_tasks="$(count_pending_tasks "$spec_dir")"
    done_tasks="$(count_done_tasks "$spec_dir")"

    if [[ "$pending_tasks" -eq 0 ]]; then
      _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$iterations_completed"
      session_clear_state
      return "$EXIT_OK"
    fi

    separator "Iteration ${loop_index} of ${MAX_LOOPS}"

    local iter_dir="${session_path}/$(printf '%02d' "$loop_index")"
    mkdir -p "$iter_dir"

    # ── CAPTURE GIT STATE BEFORE BUILD ──────────────
    local before_sha
    before_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

    # ── BUILD ──────────────────────────────────────
    phase "build"
    local build_prompt="${iter_dir}/build_prompt.md"
    local build_output="${iter_dir}/build_output.log"
    write_build_prompt "$spec_dir" "$build_prompt"

    if ! run_claude "$build_prompt" "$build_output"; then
      die "Build run failed. Check log: $build_output"
    fi

    local build_cost
    build_cost="$(extract_cost "$build_output")"
    total_cost=$(echo "$total_cost + $build_cost" | bc 2>/dev/null || echo "$total_cost")

    # Capture commit SHA after build
    local after_build_sha
    after_build_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

    # Check promise tags
    if output_has_tag "$build_output" "COMPLETE"; then
      step_ok "All tasks complete"
      iterations_completed=$((iterations_completed + 1))
      _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$iterations_completed"
      return "$EXIT_OK"
    fi

    if output_has_tag "$build_output" "BLOCKED"; then
      step_error "Build is BLOCKED"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
      return "$EXIT_BLOCKED"
    fi

    local build_status
    build_status="$(parse_kv_value "BUILD_STATUS" "$build_output")"
    [[ -n "$build_status" ]] || die "Build output missing BUILD_STATUS. Log: $build_output"

    case "$build_status" in
      NO_PENDING_TASKS)
        step_ok "No pending tasks"
        iterations_completed=$((iterations_completed + 1))
        _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$iterations_completed"
        return "$EXIT_OK"
        ;;
      BLOCKED)
        step_error "Build reported BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
        ;;
      COMPLETED_TASK)
        ;; # Continue to review
      *)
        die "Unexpected BUILD_STATUS: '$build_status'. Log: $build_output"
        ;;
    esac

    # ── DETECT PROGRESS (for circuit breaker) ──────
    # Done in parent shell so side effects are preserved (not in subshell)
    local made_progress="false"
    local current_head
    current_head=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ -z "$CB_LAST_COMMIT" || "$current_head" != "$CB_LAST_COMMIT" ]]; then
      made_progress="true"
    fi

    # ── SKIP REVIEW (if requested) ─────────────────
    if [[ "$SKIP_REVIEW" == "true" ]]; then
      done_tasks="$(count_done_tasks "$spec_dir")"
      pending_tasks="$(count_pending_tasks "$spec_dir")"
      task_complete "Task done" "$pending_tasks"
      cb_record "$made_progress"
      _session_log_iteration "$session_path" "$loop_index" "skip-review" "$build_cost" "$after_build_sha"
      iterations_completed=$((iterations_completed + 1))
      loop_index=$((loop_index + 1))
      continue
    fi

    # ── REVIEW ─────────────────────────────────────
    phase "review"
    local review_prompt="${iter_dir}/review_prompt.md"
    local review_output="${iter_dir}/review_output.log"
    # Pass before_sha so review is scoped to just this task's changes
    write_review_prompt "$spec_dir" "$review_prompt" "$before_sha"

    if ! run_claude "$review_prompt" "$review_output"; then
      die "Review run failed. Check log: $review_output"
    fi

    local review_cost
    review_cost="$(extract_cost "$review_output")"
    total_cost=$(echo "$total_cost + $review_cost" | bc 2>/dev/null || echo "$total_cost")

    if output_has_tag "$review_output" "BLOCKED"; then
      step_error "Review is BLOCKED"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
      return "$EXIT_BLOCKED"
    fi

    local review_status must_fix_count should_fix_count
    review_status="$(parse_kv_value "REVIEW_STATUS" "$review_output")"
    must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$review_output")")"
    should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$review_output")")"

    local needs_fix="false"
    if [[ "$review_status" == "FAIL" || "$must_fix_count" -gt 0 || "$should_fix_count" -gt 0 ]]; then
      needs_fix="true"
    fi

    if [[ "$needs_fix" == "false" ]]; then
      step_ok "PASS  ${C_DIM}0 must-fix ${SYM_DIAMOND} 0 should-fix${C_RESET}"
      done_tasks="$(count_done_tasks "$spec_dir")"
      pending_tasks="$(count_pending_tasks "$spec_dir")"
      task_complete "Task done" "$pending_tasks"
      cb_record "$made_progress"
      local iter_cost
      iter_cost=$(echo "$build_cost + $review_cost" | bc 2>/dev/null || echo "0")
      _session_log_iteration "$session_path" "$loop_index" "pass" "$iter_cost" "$after_build_sha"
      iterations_completed=$((iterations_completed + 1))
      loop_index=$((loop_index + 1))
      continue
    fi

    step_warn "FAIL  ${must_fix_count} must-fix ${SYM_DIAMOND} ${should_fix_count} should-fix"

    # ── FIX LOOP ───────────────────────────────────
    local fix_try=1
    local fix_passed="false"
    while [[ "$fix_try" -le "$MAX_REVIEW_FIX_LOOPS" ]]; do
      phase "fix (attempt ${fix_try}/${MAX_REVIEW_FIX_LOOPS})"

      local fix_prompt="${iter_dir}/fix_prompt_${fix_try}.md"
      local fix_output="${iter_dir}/fix_output_${fix_try}.log"
      write_fix_prompt "$spec_dir" "$review_output" "$fix_prompt"

      if ! run_claude "$fix_prompt" "$fix_output"; then
        die "Fix build run failed. Check log: $fix_output"
      fi

      local fix_cost
      fix_cost="$(extract_cost "$fix_output")"
      total_cost=$(echo "$total_cost + $fix_cost" | bc 2>/dev/null || echo "$total_cost")

      if output_has_tag "$fix_output" "BLOCKED"; then
        step_error "Fix build is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
      fi

      # Re-review — generate a fresh prompt scoped to the full diff
      phase "review (recheck)"
      review_output="${iter_dir}/review_recheck_${fix_try}.log"
      local recheck_prompt="${iter_dir}/review_recheck_prompt_${fix_try}.md"
      write_review_prompt "$spec_dir" "$recheck_prompt" "$before_sha"

      if ! run_claude "$recheck_prompt" "$review_output"; then
        die "Review recheck failed. Check log: $review_output"
      fi

      local recheck_cost
      recheck_cost="$(extract_cost "$review_output")"
      total_cost=$(echo "$total_cost + $recheck_cost" | bc 2>/dev/null || echo "$total_cost")

      if output_has_tag "$review_output" "BLOCKED"; then
        step_error "Review recheck is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
      fi

      review_status="$(parse_kv_value "REVIEW_STATUS" "$review_output")"
      must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$review_output")")"
      should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$review_output")")"

      if [[ "$review_status" == "PASS" && "$must_fix_count" -eq 0 && "$should_fix_count" -eq 0 ]]; then
        step_ok "PASS after fix attempt ${fix_try}"
        fix_passed="true"
        break
      fi

      step_warn "Still failing: ${must_fix_count} must-fix ${SYM_DIAMOND} ${should_fix_count} should-fix"
      fix_try=$((fix_try + 1))
    done

    # Use fix_passed flag — consistent with the break condition
    if [[ "$fix_passed" != "true" ]]; then
      die "Review still failing after ${MAX_REVIEW_FIX_LOOPS} fix attempts. Log: $review_output"
    fi

    # Re-check progress after fixes
    current_head=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ -z "$CB_LAST_COMMIT" || "$current_head" != "$CB_LAST_COMMIT" ]]; then
      made_progress="true"
    fi

    done_tasks="$(count_done_tasks "$spec_dir")"
    pending_tasks="$(count_pending_tasks "$spec_dir")"
    task_complete "Task done" "$pending_tasks"
    cb_record "$made_progress"

    local after_fix_sha
    after_fix_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    _session_log_iteration "$session_path" "$loop_index" "pass-after-fix" "0" "$after_fix_sha"

    iterations_completed=$((iterations_completed + 1))
    loop_index=$((loop_index + 1))
  done

  # Reached max loops
  if [[ "$ONCE" == "true" ]]; then
    pending_tasks="$(count_pending_tasks "$spec_dir")"
    step_ok "${C_BOLD}Single cycle completed${C_RESET} ${C_DIM}(--once). ${pending_tasks} tasks may remain.${C_RESET}"
    _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "ONCE" "$iterations_completed"
    return "$EXIT_OK"
  fi

  _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "MAX_ITERATIONS" "$iterations_completed"
  die "Reached max loops ($MAX_LOOPS) with pending tasks still present"
}

# ── Summary box ──────────────────────────────────────

_loop_complete() {
  local session_path="$1"
  local spec_name="$2"
  local total_tasks="$3"
  local start_epoch="$4"
  local total_cost="$5"
  local iterations="${6:-0}"

  local end_epoch
  end_epoch=$(date +%s)
  local duration=$((end_epoch - start_epoch))
  local dur_str
  dur_str=$(format_duration "$duration")
  local cost_str
  cost_str=$(format_cost "$total_cost")

  echo ""
  box_header "Complete" 52
  box_empty
  box_line "  ${C_GREEN}${SYM_OK}${C_RESET} All tasks done"
  box_empty
  box_line "  Tasks       ${total_tasks} completed"
  box_line "  Iterations  ${iterations}"
  box_line "  Duration    ${dur_str}"
  box_line "  Cost        ${cost_str}"
  box_empty
  box_footer

  _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "COMPLETE" "$iterations"
}

# ── Session JSON helpers ─────────────────────────────

_session_json_init() {
  local session_path="$1"
  local spec_dir="$2"
  local spec_name="$3"

  cat > "${session_path}/session.json" <<EOF
{
  "version": "$SPECLOOP_VERSION",
  "spec": "$spec_dir",
  "spec_name": "$spec_name",
  "started_at": "$(timestamp_iso)",
  "iterations": []
}
EOF
}

_session_json_finalize() {
  local session_path="$1"
  local start_epoch="$2"
  local total_cost="$3"
  local exit_reason="$4"
  local iterations="$5"

  local end_epoch
  end_epoch=$(date +%s)
  local duration=$((end_epoch - start_epoch))

  local json_file="${session_path}/session.json"
  [[ -f "$json_file" ]] || return

  local tmp="${json_file}.tmp"
  jq --arg ended "$(timestamp_iso)" \
     --argjson dur "$duration" \
     --argjson cost "$total_cost" \
     --arg reason "$exit_reason" \
     --argjson iters "$iterations" \
     '. + {ended_at: $ended, duration_seconds: $dur, total_cost_usd: $cost, exit_reason: $reason, total_iterations: $iters}' \
     "$json_file" > "$tmp" 2>/dev/null && mv "$tmp" "$json_file" || true
}

_session_log_iteration() {
  local session_path="$1"
  local index="$2"
  local outcome="$3"
  local cost="$4"
  local commit_sha="${5:-}"

  # Append to session.md
  local md_file="${session_path}/session.md"
  if [[ ! -f "$md_file" ]]; then
    echo "# Session Log" > "$md_file"
    echo "" >> "$md_file"
  fi

  echo "## Iteration ${index} — $(timestamp_human)" >> "$md_file"
  echo "- Outcome: ${outcome}" >> "$md_file"
  echo "- Cost: $(format_cost "$cost")" >> "$md_file"
  if [[ -n "$commit_sha" ]]; then
    echo "- Commit: ${commit_sha}" >> "$md_file"
  fi
  echo "" >> "$md_file"
}
