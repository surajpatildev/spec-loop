#!/usr/bin/env bash
# spec-loop main orchestration — build → review → fix loop
#
# Session output is minimal:
#   .spec-loop/sessions/<timestamp>/
#     session.json   — machine-readable analytics
#     session.md     — human-readable summary
#     01.md          — iteration 1 (build output, review output, fix output)
#     02.md          — iteration 2
#     ...

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
    mkdir -p "$session_path"
  else
    local session_ts
    session_ts="$(timestamp)"
    session_path="${SESSION_DIR}/${session_ts}"
    loop_index=1
    mkdir -p "$session_path"
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

    # Iteration file — single .md per iteration
    local iter_file="${session_path}/$(printf '%02d' "$loop_index").md"
    local iter_num
    iter_num=$(printf '%02d' "$loop_index")

    # Temp file for raw NDJSON (deleted after extraction)
    local ndjson_tmp
    ndjson_tmp=$(mktemp)

    # Prompt temp file (not saved)
    local prompt_tmp
    prompt_tmp=$(mktemp)

    # ── CAPTURE GIT STATE BEFORE BUILD ──────────────
    local before_sha
    before_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

    # ── BUILD ──────────────────────────────────────
    phase "build"
    write_build_prompt "$spec_dir" "$prompt_tmp"

    if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
      rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
      die "Build run failed"
    fi

    # Extract data from NDJSON
    local build_cost build_duration build_text build_status
    build_cost="$(extract_cost "$ndjson_tmp")"
    build_duration="$(extract_duration_ms "$ndjson_tmp")"
    build_text="$(extract_parseable_text "$ndjson_tmp")"
    build_status="$(parse_kv_value "BUILD_STATUS" "$ndjson_tmp")"
    total_cost=$(echo "$total_cost + $build_cost" | bc 2>/dev/null || echo "$total_cost")

    local build_has_complete="false"
    output_has_tag "$ndjson_tmp" "COMPLETE" && build_has_complete="true"
    local build_has_blocked="false"
    output_has_tag "$ndjson_tmp" "BLOCKED" && build_has_blocked="true"

    # Done with NDJSON — clean up temps
    rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

    # Write iteration file — build section
    local build_cost_str
    build_cost_str=$(format_cost "$build_cost")
    local build_dur_s=$(( build_duration / 1000 ))
    local build_dur_str
    build_dur_str=$(format_duration "$build_dur_s")

    {
      echo "# Iteration ${loop_index}"
      echo ""
      echo "## Build"
      echo "- Status: ${build_status:-unknown}"
      echo "- Duration: ${build_dur_str}"
      echo "- Cost: ${build_cost_str}"
      echo ""
      echo "### Output"
      echo ""
      echo "$build_text"
    } > "$iter_file"

    # Capture commit SHA after build
    local after_build_sha
    after_build_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

    # Check promise tags
    if [[ "$build_has_complete" == "true" ]]; then
      step_ok "All tasks complete"
      iterations_completed=$((iterations_completed + 1))
      _session_log "$session_path" "$loop_index" "complete" "$build_cost" "$after_build_sha"
      _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$iterations_completed"
      return "$EXIT_OK"
    fi

    if [[ "$build_has_blocked" == "true" ]]; then
      step_error "Build is BLOCKED"
      _session_log "$session_path" "$loop_index" "blocked" "$build_cost" "$after_build_sha"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
      return "$EXIT_BLOCKED"
    fi

    [[ -n "$build_status" ]] || die "Build output missing BUILD_STATUS"

    case "$build_status" in
      NO_PENDING_TASKS)
        step_ok "No pending tasks"
        iterations_completed=$((iterations_completed + 1))
        _session_log "$session_path" "$loop_index" "no-pending" "$build_cost" "$after_build_sha"
        _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$iterations_completed"
        return "$EXIT_OK"
        ;;
      BLOCKED)
        step_error "Build reported BLOCKED"
        _session_log "$session_path" "$loop_index" "blocked" "$build_cost" "$after_build_sha"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
        ;;
      COMPLETED_TASK)
        ;; # Continue to review
      *)
        die "Unexpected BUILD_STATUS: '$build_status'"
        ;;
    esac

    # ── DETECT PROGRESS (for circuit breaker) ──────
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
      _session_log "$session_path" "$loop_index" "skip-review" "$build_cost" "$after_build_sha"
      iterations_completed=$((iterations_completed + 1))
      loop_index=$((loop_index + 1))
      continue
    fi

    # ── REVIEW ─────────────────────────────────────
    phase "review"
    ndjson_tmp=$(mktemp)
    prompt_tmp=$(mktemp)
    write_review_prompt "$spec_dir" "$prompt_tmp" "$before_sha"

    if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
      rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
      die "Review run failed"
    fi

    local review_cost review_duration review_text review_status must_fix_count should_fix_count
    review_cost="$(extract_cost "$ndjson_tmp")"
    review_duration="$(extract_duration_ms "$ndjson_tmp")"
    review_text="$(extract_parseable_text "$ndjson_tmp")"
    review_status="$(parse_kv_value "REVIEW_STATUS" "$ndjson_tmp")"
    must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$ndjson_tmp")")"
    should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$ndjson_tmp")")"
    total_cost=$(echo "$total_cost + $review_cost" | bc 2>/dev/null || echo "$total_cost")

    local review_has_blocked="false"
    output_has_tag "$ndjson_tmp" "BLOCKED" && review_has_blocked="true"

    rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

    # Append review section to iteration file
    local review_cost_str
    review_cost_str=$(format_cost "$review_cost")
    local review_dur_s=$(( review_duration / 1000 ))
    local review_dur_str
    review_dur_str=$(format_duration "$review_dur_s")

    {
      echo ""
      echo "---"
      echo ""
      echo "## Review"
      echo "- Status: ${review_status:-unknown}"
      echo "- Must-fix: ${must_fix_count}"
      echo "- Should-fix: ${should_fix_count}"
      echo "- Duration: ${review_dur_str}"
      echo "- Cost: ${review_cost_str}"
      echo ""
      echo "### Output"
      echo ""
      echo "$review_text"
    } >> "$iter_file"

    if [[ "$review_has_blocked" == "true" ]]; then
      step_error "Review is BLOCKED"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
      return "$EXIT_BLOCKED"
    fi

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
      _session_log "$session_path" "$loop_index" "pass" "$iter_cost" "$after_build_sha"
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

      ndjson_tmp=$(mktemp)
      prompt_tmp=$(mktemp)

      # Fix prompt reads the review findings from the iteration .md
      write_fix_prompt "$spec_dir" "$iter_file" "$prompt_tmp"

      if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
        rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
        die "Fix build run failed"
      fi

      local fix_cost fix_text
      fix_cost="$(extract_cost "$ndjson_tmp")"
      fix_text="$(extract_parseable_text "$ndjson_tmp")"
      total_cost=$(echo "$total_cost + $fix_cost" | bc 2>/dev/null || echo "$total_cost")

      local fix_has_blocked="false"
      output_has_tag "$ndjson_tmp" "BLOCKED" && fix_has_blocked="true"

      rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

      # Append fix section to iteration file
      local fix_cost_str
      fix_cost_str=$(format_cost "$fix_cost")
      {
        echo ""
        echo "---"
        echo ""
        echo "## Fix (attempt ${fix_try})"
        echo "- Cost: ${fix_cost_str}"
        echo ""
        echo "### Output"
        echo ""
        echo "$fix_text"
      } >> "$iter_file"

      if [[ "$fix_has_blocked" == "true" ]]; then
        step_error "Fix build is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
      fi

      # Re-review
      phase "review (recheck)"
      ndjson_tmp=$(mktemp)
      prompt_tmp=$(mktemp)
      write_review_prompt "$spec_dir" "$prompt_tmp" "$before_sha"

      if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
        rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
        die "Review recheck failed"
      fi

      local recheck_cost recheck_text
      recheck_cost="$(extract_cost "$ndjson_tmp")"
      recheck_text="$(extract_parseable_text "$ndjson_tmp")"
      total_cost=$(echo "$total_cost + $recheck_cost" | bc 2>/dev/null || echo "$total_cost")

      review_status="$(parse_kv_value "REVIEW_STATUS" "$ndjson_tmp")"
      must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$ndjson_tmp")")"
      should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$ndjson_tmp")")"

      local recheck_has_blocked="false"
      output_has_tag "$ndjson_tmp" "BLOCKED" && recheck_has_blocked="true"

      rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

      # Append recheck section to iteration file
      local recheck_cost_str
      recheck_cost_str=$(format_cost "$recheck_cost")
      {
        echo ""
        echo "---"
        echo ""
        echo "## Review (recheck ${fix_try})"
        echo "- Status: ${review_status:-unknown}"
        echo "- Must-fix: ${must_fix_count}"
        echo "- Should-fix: ${should_fix_count}"
        echo "- Cost: ${recheck_cost_str}"
        echo ""
        echo "### Output"
        echo ""
        echo "$recheck_text"
      } >> "$iter_file"

      if [[ "$recheck_has_blocked" == "true" ]]; then
        step_error "Review recheck is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$iterations_completed"
        return "$EXIT_BLOCKED"
      fi

      if [[ "$review_status" == "PASS" && "$must_fix_count" -eq 0 && "$should_fix_count" -eq 0 ]]; then
        step_ok "PASS after fix attempt ${fix_try}"
        fix_passed="true"
        break
      fi

      step_warn "Still failing: ${must_fix_count} must-fix ${SYM_DIAMOND} ${should_fix_count} should-fix"
      fix_try=$((fix_try + 1))
    done

    if [[ "$fix_passed" != "true" ]]; then
      die "Review still failing after ${MAX_REVIEW_FIX_LOOPS} fix attempts"
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
    local total_iter_cost
    total_iter_cost=$(echo "$build_cost + $review_cost" | bc 2>/dev/null || echo "0")
    _session_log "$session_path" "$loop_index" "pass-after-fix" "$total_iter_cost" "$after_fix_sha"

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

# ── Session summary log (session.md) ─────────────────

_session_log() {
  local session_path="$1"
  local index="$2"
  local outcome="$3"
  local cost="$4"
  local commit_sha="${5:-}"

  local md_file="${session_path}/session.md"
  if [[ ! -f "$md_file" ]]; then
    echo "# Session Log" > "$md_file"
    echo "" >> "$md_file"
  fi

  local cost_str
  cost_str=$(format_cost "$cost")
  local short_sha=""
  [[ -n "$commit_sha" ]] && short_sha="${commit_sha:0:7}"

  {
    echo "## Iteration ${index} — $(timestamp_human)"
    echo "- Outcome: ${outcome}"
    echo "- Cost: ${cost_str}"
    [[ -n "$short_sha" ]] && echo "- Commit: ${short_sha}"
    echo ""
  } >> "$md_file"
}
