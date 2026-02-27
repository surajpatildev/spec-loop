#!/usr/bin/env bash
# spec-loop main orchestration — build -> review -> fix loop
#
# Session output:
#   .spec-loop/sessions/<timestamp>/
#     session.json   — high-level machine telemetry
#     session.md     — concise iteration summaries
#     run.md         — full human-readable run log
#
# Resume is phase-aware: if the loop crashes after build but before review,
# --resume will skip straight to review instead of re-running build.

_RUNLOG_LAST_ITERATION=""

cmd_run() {
  preflight

  local spec_dir
  spec_dir="$(resolve_spec_dir)"
  local spec_name
  spec_name="$(get_spec_name "$spec_dir")"

  cb_init
  session_init

  local session_path loop_index resume_phase="" resume_before_sha=""
  local continuation_mode="false"

  if [[ "$RESUME" == "true" ]] && session_load_state; then
    spec_dir="$RESUME_SPEC_DIR"
    spec_name="$(get_spec_name "$spec_dir")"
    session_path="$RESUME_SESSION_PATH"
    loop_index="$RESUME_LOOP_INDEX"
    resume_phase="$RESUME_PHASE"
    resume_before_sha="$RESUME_BEFORE_SHA"
    step_info "Resuming session for ${spec_name} at iteration ${loop_index} (phase: ${resume_phase})"
    mkdir -p "$session_path"
    [[ -f "${session_path}/session.json" ]] || _session_json_init "$session_path" "$spec_dir" "$spec_name"
    [[ -f "${session_path}/run.md" ]] || _session_markdown_init "$session_path" "$spec_name" "$spec_dir"
  else
    local continuation_path
    continuation_path="$(session_continuation_for_spec "$spec_dir" || true)"
    if [[ -n "$continuation_path" && -d "$continuation_path" ]]; then
      continuation_mode="true"
      session_path="$continuation_path"
      mkdir -p "$session_path"
      loop_index=$(( $(session_iterations_count "$session_path") + 1 ))
      step_info "Continuing session $(basename "$session_path") at iteration ${loop_index}"
      [[ -f "${session_path}/session.json" ]] || _session_json_init "$session_path" "$spec_dir" "$spec_name"
      [[ -f "${session_path}/run.md" ]] || _session_markdown_init "$session_path" "$spec_name" "$spec_dir"
    else
      local session_ts session_slug
      session_ts="$(timestamp)"
      session_slug="$(slugify "$spec_name")"
      session_path="${SESSION_DIR}/${session_ts}_${session_slug}"
      loop_index=1
      mkdir -p "$session_path"
      _session_json_init "$session_path" "$spec_dir" "$spec_name"
      _session_markdown_init "$session_path" "$spec_name" "$spec_dir"
    fi
  fi

  local total_tasks done_tasks remaining_tasks
  total_tasks="$(count_total_tasks "$spec_dir")"
  done_tasks="$(count_done_tasks "$spec_dir")"
  remaining_tasks="$(count_remaining_tasks "$spec_dir")"

  print_header

  local branch
  branch="$(get_current_branch)"

  box_header "Spec" 52
  box_empty
  box_line "  ${spec_name}"
  box_line "  $(progress_bar "$done_tasks" "$total_tasks" 16 "done") ${SYM_DIAMOND} ${remaining_tasks} remaining"
  box_line "  ${C_DIM}${branch}${C_RESET}"
  if [[ "$MAX_TASKS_PER_RUN" -gt 0 ]]; then
    box_line "  Task budget  ${MAX_TASKS_PER_RUN} this run"
  fi
  box_empty
  box_footer

  local total_cost=0
  local start_epoch
  local total_iterations_base=0
  if [[ -f "${session_path}/session.json" ]]; then
    total_cost="$(session_total_cost "$session_path")"
    total_iterations_base="$(session_total_iterations "$session_path")"
    start_epoch="$(session_started_epoch "$session_path")"
  else
    start_epoch=$(date +%s)
  fi
  local iterations_completed=0

  _session_runlog_invocation_header "$session_path" "$RESUME" "$continuation_mode"

  while [[ "$loop_index" -le "$MAX_LOOPS" ]]; do
    if ! cb_check; then
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "CIRCUIT_OPEN" "$((total_iterations_base + iterations_completed))"
      session_clear_state
      return "$EXIT_CIRCUIT_OPEN"
    fi

    remaining_tasks="$(count_remaining_tasks "$spec_dir")"
    done_tasks="$(count_done_tasks "$spec_dir")"

    if [[ "$remaining_tasks" -eq 0 ]]; then
      _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$((total_iterations_base + iterations_completed))"
      session_clear_state
      return "$EXIT_OK"
    fi

    if [[ "$MAX_TASKS_PER_RUN" -gt 0 && "$iterations_completed" -ge "$MAX_TASKS_PER_RUN" ]]; then
      step_ok "Reached task budget (${MAX_TASKS_PER_RUN}) for this run"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "TASK_LIMIT" "$((total_iterations_base + iterations_completed))"
      session_clear_state
      return "$EXIT_OK"
    fi

    local next_task_file next_task_name
    next_task_file="$(find_next_task "$spec_dir")"
    if [[ -z "$next_task_file" ]]; then
      next_task_file="$(find_open_task "$spec_dir")"
    fi

    next_task_name=""
    if [[ -n "$next_task_file" ]]; then
      next_task_name="$(get_task_name "$next_task_file")"
    fi

    if [[ -n "$next_task_name" ]]; then
      separator "Iteration ${loop_index} ${SYM_DIAMOND} ${next_task_name}"
    else
      separator "Iteration ${loop_index} of ${MAX_LOOPS}"
    fi

    _session_runlog_iteration_header "$session_path" "$loop_index" "$next_task_name"

    local iteration_start_epoch
    iteration_start_epoch=$(date +%s)

    local before_sha="" after_build_sha=""
    local build_cost=0 build_status="" build_duration=0 build_text=""
    local review_cost=0 review_duration=0 review_text=""
    local fix_total_cost=0
    local must_fix_count=0 should_fix_count=0
    local review_findings=""

    if [[ "$resume_phase" == "review" || "$resume_phase" == "fix" ]]; then
      step_info "Skipping build (already completed, resuming at ${resume_phase})"
      before_sha="$resume_before_sha"
      after_build_sha=$(get_head_sha)
      build_status="COMPLETED_TASK"
      session_save_state "$spec_dir" "$loop_index" "$session_path" "$resume_phase" "$before_sha"
    else
      session_save_state "$spec_dir" "$loop_index" "$session_path" "build" ""

      before_sha=$(get_head_sha)

      phase "build"
      local ndjson_tmp prompt_tmp
      ndjson_tmp=$(mktemp)
      prompt_tmp=$(mktemp)
      write_build_prompt "$spec_dir" "$prompt_tmp"
      local build_prompt_text
      build_prompt_text="$(cat "$prompt_tmp")"

      if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
        rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
        die "Build run failed"
      fi

      build_cost="$(extract_cost "$ndjson_tmp")"
      build_duration="$(extract_duration_ms "$ndjson_tmp")"
      build_text="$(extract_parseable_text "$ndjson_tmp")"
      local build_claude_session_id
      build_claude_session_id="$(extract_claude_session_id "$ndjson_tmp")"
      build_status="$(parse_kv_value "BUILD_STATUS" "$ndjson_tmp")"
      total_cost=$(echo "$total_cost + $build_cost" | bc 2>/dev/null || echo "$total_cost")

      local build_has_complete="false"
      output_has_tag "$ndjson_tmp" "COMPLETE" && build_has_complete="true"
      local build_has_blocked="false"
      output_has_tag "$ndjson_tmp" "BLOCKED" && build_has_blocked="true"

      rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

      _session_runlog_phase "$session_path" "$loop_index" "Build" "${build_status:-unknown}" "$build_cost" "$build_duration" "$build_text" "$build_prompt_text" "$build_claude_session_id"

      after_build_sha=$(get_head_sha)

      if [[ "$build_has_complete" == "true" ]]; then
        step_ok "All tasks complete"
        iterations_completed=$((iterations_completed + 1))
        local iter_seconds
        iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
        _session_log "$session_path" "$loop_index" "complete" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0
        _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$((total_iterations_base + iterations_completed))"
        session_clear_state
        return "$EXIT_OK"
      fi

      if [[ "$build_has_blocked" == "true" ]]; then
        step_error "Build is BLOCKED"
        local iter_seconds
        iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
        _session_log "$session_path" "$loop_index" "blocked" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
        session_clear_state
        return "$EXIT_BLOCKED"
      fi

      if [[ -z "$build_status" ]]; then
        step_error "Build output missing BUILD_STATUS. Last lines of output:"
        echo "$build_text" | tail -5 | while IFS= read -r dbg_line; do
          step_error "  $dbg_line"
        done
        die "Build output missing BUILD_STATUS — model did not comply with prompt format"
      fi

      case "$build_status" in
        NO_PENDING_TASKS)
          remaining_tasks="$(count_remaining_tasks "$spec_dir")"
          if [[ "$remaining_tasks" -gt 0 ]]; then
            step_error "No pending tasks, but ${remaining_tasks} tasks remain (likely blocked/in-review)"
            local iter_seconds
            iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
            _session_log "$session_path" "$loop_index" "blocked-no-pending" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0
            _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
            session_clear_state
            return "$EXIT_BLOCKED"
          fi
          step_ok "No pending tasks"
          iterations_completed=$((iterations_completed + 1))
          local iter_seconds
          iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
          _session_log "$session_path" "$loop_index" "no-pending" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0
          _loop_complete "$session_path" "$spec_name" "$total_tasks" "$start_epoch" "$total_cost" "$((total_iterations_base + iterations_completed))"
          session_clear_state
          return "$EXIT_OK"
          ;;
        BLOCKED)
          step_error "Build reported BLOCKED"
          local iter_seconds
          iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
          _session_log "$session_path" "$loop_index" "blocked" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0
          _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
          session_clear_state
          return "$EXIT_BLOCKED"
          ;;
        COMPLETED_TASK)
          if [[ -n "$next_task_file" && -f "$next_task_file" ]]; then
            set_task_status "$next_task_file" "in-review" || true
          fi
          ;;
        *)
          die "Unexpected BUILD_STATUS: '$build_status'"
          ;;
      esac

      session_save_state "$spec_dir" "$loop_index" "$session_path" "review" "$before_sha"
    fi

    resume_phase=""
    resume_before_sha=""

    local made_progress="false"
    local current_head
    current_head=$(get_head_sha)
    if [[ -z "$CB_LAST_COMMIT" || "$current_head" != "$CB_LAST_COMMIT" ]]; then
      made_progress="true"
    fi

    if [[ "$SKIP_REVIEW" == "true" ]]; then
      if [[ -n "$next_task_file" && -f "$next_task_file" ]]; then
        set_task_status "$next_task_file" "in-review" || true
      fi

      remaining_tasks="$(count_remaining_tasks "$spec_dir")"
      task_complete "Task ready for review" "$remaining_tasks"
      cb_record "$made_progress"

      local iter_seconds
      iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
      _session_log "$session_path" "$loop_index" "skip-review" "$build_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" 0 0

      iterations_completed=$((iterations_completed + 1))
      loop_index=$((loop_index + 1))
      continue
    fi

    phase "review"
    local ndjson_tmp prompt_tmp
    ndjson_tmp=$(mktemp)
    prompt_tmp=$(mktemp)
    write_review_prompt "$spec_dir" "$prompt_tmp" "$before_sha"
    local review_prompt_text
    review_prompt_text="$(cat "$prompt_tmp")"

    if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
      rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
      die "Review run failed"
    fi

    review_cost="$(extract_cost "$ndjson_tmp")"
    review_duration="$(extract_duration_ms "$ndjson_tmp")"
    review_text="$(extract_parseable_text "$ndjson_tmp")"
    local review_claude_session_id
    review_claude_session_id="$(extract_claude_session_id "$ndjson_tmp")"
    review_status="$(parse_kv_value "REVIEW_STATUS" "$ndjson_tmp")"
    must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$ndjson_tmp")")"
    should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$ndjson_tmp")")"
    total_cost=$(echo "$total_cost + $review_cost" | bc 2>/dev/null || echo "$total_cost")

    review_findings="$review_text"

    local review_has_blocked="false"
    output_has_tag "$ndjson_tmp" "BLOCKED" && review_has_blocked="true"

    rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

    local review_phase_status
    review_phase_status="${review_status:-unknown}; must_fix=${must_fix_count}; should_fix=${should_fix_count}"
    _session_runlog_phase "$session_path" "$loop_index" "Review" "$review_phase_status" "$review_cost" "$review_duration" "$review_text" "$review_prompt_text" "$review_claude_session_id"

    if [[ "$review_has_blocked" == "true" ]]; then
      step_error "Review is BLOCKED"
      _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
      session_clear_state
      return "$EXIT_BLOCKED"
    fi

    local needs_fix="false"
    if [[ "$review_status" == "FAIL" || "$must_fix_count" -gt 0 || "$should_fix_count" -gt 0 ]]; then
      needs_fix="true"
    fi

    if [[ "$needs_fix" == "false" ]]; then
      if [[ -n "$next_task_file" && -f "$next_task_file" ]]; then
        set_task_status "$next_task_file" "done" || true
      fi

      step_ok "PASS  ${C_DIM}0 must-fix ${SYM_DIAMOND} 0 should-fix${C_RESET}"
      remaining_tasks="$(count_remaining_tasks "$spec_dir")"
      task_complete "Task done" "$remaining_tasks"
      cb_record "$made_progress"

      local iter_cost
      iter_cost=$(echo "$build_cost + $review_cost" | bc 2>/dev/null || echo "0")
      local iter_seconds
      iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
      _session_log "$session_path" "$loop_index" "pass" "$iter_cost" "$after_build_sha" "$next_task_name" "$iter_seconds" "$must_fix_count" "$should_fix_count"

      iterations_completed=$((iterations_completed + 1))
      loop_index=$((loop_index + 1))
      continue
    fi

    step_warn "FAIL  ${must_fix_count} must-fix ${SYM_DIAMOND} ${should_fix_count} should-fix"

    session_save_state "$spec_dir" "$loop_index" "$session_path" "fix" "$before_sha"

    local fix_try=1
    local fix_passed="false"
    while [[ "$fix_try" -le "$MAX_REVIEW_FIX_LOOPS" ]]; do
      phase "fix (attempt ${fix_try}/${MAX_REVIEW_FIX_LOOPS})"

      ndjson_tmp=$(mktemp)
      prompt_tmp=$(mktemp)

      write_fix_prompt "$spec_dir" "$review_findings" "$prompt_tmp"
      local fix_prompt_text
      fix_prompt_text="$(cat "$prompt_tmp")"

      if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
        rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
        die "Fix build run failed"
      fi

      local fix_cost fix_duration fix_text
      fix_cost="$(extract_cost "$ndjson_tmp")"
      fix_duration="$(extract_duration_ms "$ndjson_tmp")"
      fix_text="$(extract_parseable_text "$ndjson_tmp")"
      local fix_claude_session_id
      fix_claude_session_id="$(extract_claude_session_id "$ndjson_tmp")"
      total_cost=$(echo "$total_cost + $fix_cost" | bc 2>/dev/null || echo "$total_cost")
      fix_total_cost=$(echo "$fix_total_cost + $fix_cost" | bc 2>/dev/null || echo "$fix_total_cost")

      local fix_has_blocked="false"
      output_has_tag "$ndjson_tmp" "BLOCKED" && fix_has_blocked="true"

      rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

      _session_runlog_phase "$session_path" "$loop_index" "Fix (attempt ${fix_try})" "applied" "$fix_cost" "$fix_duration" "$fix_text" "$fix_prompt_text" "$fix_claude_session_id"

      if [[ "$fix_has_blocked" == "true" ]]; then
        step_error "Fix build is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
        session_clear_state
        return "$EXIT_BLOCKED"
      fi

      phase "review (recheck)"
      ndjson_tmp=$(mktemp)
      prompt_tmp=$(mktemp)
      write_review_prompt "$spec_dir" "$prompt_tmp" "$before_sha"
      local recheck_prompt_text
      recheck_prompt_text="$(cat "$prompt_tmp")"

      if ! run_claude "$prompt_tmp" "$ndjson_tmp"; then
        rm -f "$prompt_tmp" "$ndjson_tmp" 2>/dev/null
        die "Review recheck failed"
      fi

      local recheck_cost recheck_duration recheck_text
      recheck_cost="$(extract_cost "$ndjson_tmp")"
      recheck_duration="$(extract_duration_ms "$ndjson_tmp")"
      recheck_text="$(extract_parseable_text "$ndjson_tmp")"
      local recheck_claude_session_id
      recheck_claude_session_id="$(extract_claude_session_id "$ndjson_tmp")"
      total_cost=$(echo "$total_cost + $recheck_cost" | bc 2>/dev/null || echo "$total_cost")
      fix_total_cost=$(echo "$fix_total_cost + $recheck_cost" | bc 2>/dev/null || echo "$fix_total_cost")

      review_status="$(parse_kv_value "REVIEW_STATUS" "$ndjson_tmp")"
      must_fix_count="$(int_or_zero "$(parse_kv_value "MUST_FIX_COUNT" "$ndjson_tmp")")"
      should_fix_count="$(int_or_zero "$(parse_kv_value "SHOULD_FIX_COUNT" "$ndjson_tmp")")"
      review_findings="$recheck_text"

      local recheck_has_blocked="false"
      output_has_tag "$ndjson_tmp" "BLOCKED" && recheck_has_blocked="true"

      rm -f "$ndjson_tmp" "$prompt_tmp" 2>/dev/null

      local recheck_phase_status
      recheck_phase_status="${review_status:-unknown}; must_fix=${must_fix_count}; should_fix=${should_fix_count}"
      _session_runlog_phase "$session_path" "$loop_index" "Review (recheck ${fix_try})" "$recheck_phase_status" "$recheck_cost" "$recheck_duration" "$recheck_text" "$recheck_prompt_text" "$recheck_claude_session_id"

      if [[ "$recheck_has_blocked" == "true" ]]; then
        step_error "Review recheck is BLOCKED"
        _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "BLOCKED" "$((total_iterations_base + iterations_completed))"
        session_clear_state
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

    if [[ -n "$next_task_file" && -f "$next_task_file" ]]; then
      set_task_status "$next_task_file" "done" || true
    fi

    current_head=$(get_head_sha)
    if [[ -z "$CB_LAST_COMMIT" || "$current_head" != "$CB_LAST_COMMIT" ]]; then
      made_progress="true"
    fi

    remaining_tasks="$(count_remaining_tasks "$spec_dir")"
    task_complete "Task done" "$remaining_tasks"
    cb_record "$made_progress"

    local after_fix_sha
    after_fix_sha=$(get_head_sha)
    local total_iter_cost
    total_iter_cost=$(echo "$build_cost + $review_cost + $fix_total_cost" | bc 2>/dev/null || echo "0")
    local iter_seconds
    iter_seconds=$(( $(date +%s) - iteration_start_epoch ))
    _session_log "$session_path" "$loop_index" "pass-after-fix" "$total_iter_cost" "$after_fix_sha" "$next_task_name" "$iter_seconds" "$must_fix_count" "$should_fix_count"

    iterations_completed=$((iterations_completed + 1))
    loop_index=$((loop_index + 1))
  done

  printf '\a'
  if [[ "$ONCE" == "true" ]]; then
    remaining_tasks="$(count_remaining_tasks "$spec_dir")"
    step_ok "${C_BOLD}Single cycle completed${C_RESET} ${C_DIM}(--once). ${remaining_tasks} tasks may remain.${C_RESET}"
    _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "ONCE" "$((total_iterations_base + iterations_completed))"
    session_clear_state
    return "$EXIT_OK"
  fi

  _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "MAX_ITERATIONS" "$((total_iterations_base + iterations_completed))"
  session_clear_state
  die "Reached max loops ($MAX_LOOPS) with pending tasks still present"
}

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

  printf '\a'

  _session_json_finalize "$session_path" "$start_epoch" "$total_cost" "COMPLETE" "$iterations"
}

_session_json_init() {
  local session_path="$1"
  local spec_dir="$2"
  local spec_name="$3"
  local session_id
  session_id="$(basename "$session_path")"

  cat > "${session_path}/session.json" <<EOF_JSON
{
  "session_id": "$session_id",
  "version": "$SPECLOOP_VERSION",
  "spec": "$spec_dir",
  "spec_name": "$spec_name",
  "started_at": "$(timestamp_iso)",
  "max_loops": $MAX_LOOPS,
  "max_review_fix_loops": $MAX_REVIEW_FIX_LOOPS,
  "max_tasks_per_run": $MAX_TASKS_PER_RUN,
  "iterations": []
}
EOF_JSON
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

_session_markdown_init() {
  local session_path="$1"
  local spec_name="$2"
  local spec_dir="$3"

  local md_file="${session_path}/run.md"
  cat > "$md_file" <<EOF_MD
# Run Log

- Spec: ${spec_name}
- Spec path: ${spec_dir}
- Started: $(timestamp_human)

---
EOF_MD
}

_session_runlog_invocation_header() {
  local session_path="$1"
  local resume_flag="$2"
  local continuation_flag="$3"
  local md_file="${session_path}/run.md"
  local session_id
  session_id="$(basename "$session_path")"
  local mode="new"

  if [[ "$resume_flag" == "true" ]]; then
    mode="resume"
  elif [[ "$continuation_flag" == "true" ]]; then
    mode="continue"
  fi

  {
    echo ""
    echo "## Invocation — $(timestamp_human)"
    echo "- Session ID: ${session_id}"
    echo "- Mode: ${mode}"
    echo "- Flags: once=${ONCE}, max_tasks=${MAX_TASKS_PER_RUN}, max_loops=${MAX_LOOPS}, skip_review=${SKIP_REVIEW}"
    echo ""
  } >> "$md_file"
}

_session_runlog_iteration_header() {
  local session_path="$1"
  local index="$2"
  local task_name="${3:-}"
  local md_file="${session_path}/run.md"

  if [[ "$_RUNLOG_LAST_ITERATION" == "$index" ]]; then
    return
  fi
  _RUNLOG_LAST_ITERATION="$index"

  {
    echo ""
    echo "## Iteration ${index} — $(timestamp_human)"
    if [[ -n "$task_name" ]]; then
      echo "- Task: ${task_name}"
    fi
    echo ""
  } >> "$md_file"
}

_session_runlog_phase() {
  local session_path="$1"
  local index="$2"
  local phase_name="$3"
  local status="$4"
  local cost="$5"
  local duration_ms="$6"
  local output_text="$7"
  local prompt_text="${8:-}"
  local claude_session_id="${9:-}"

  local md_file="${session_path}/run.md"
  local dur_s=$((duration_ms / 1000))
  local dur_str
  dur_str=$(format_duration "$dur_s")
  local cost_str
  cost_str=$(format_cost "$cost")

  {
    echo "### ${phase_name}"
    echo "- Status: ${status}"
    echo "- Duration: ${dur_str}"
    echo "- Cost: ${cost_str}"
    if [[ -n "$claude_session_id" ]]; then
      echo "- Claude Session: ${claude_session_id}"
    fi
    echo ""
    if [[ -n "$prompt_text" ]]; then
      echo "#### Prompt"
      echo ""
      echo "$prompt_text"
      echo ""
    fi
    echo "#### Output"
    echo ""
    echo "$output_text"
    echo ""
  } >> "$md_file"
}

_session_log() {
  local session_path="$1"
  local index="$2"
  local outcome="$3"
  local cost="$4"
  local commit_sha="${5:-}"
  local task_name="${6:-}"
  local duration_seconds="${7:-0}"
  local must_fix_count="${8:-0}"
  local should_fix_count="${9:-0}"

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
    [[ -n "$task_name" ]] && echo "- Task: ${task_name}"
    echo "- Outcome: ${outcome}"
    echo "- Duration: $(format_duration "$duration_seconds")"
    echo "- Cost: ${cost_str}"
    echo "- Must-fix: ${must_fix_count}"
    echo "- Should-fix: ${should_fix_count}"
    [[ -n "$short_sha" ]] && echo "- Commit: ${short_sha}"
    echo ""
  } >> "$md_file"

  local json_file="${session_path}/session.json"
  [[ -f "$json_file" ]] || return

  local tmp="${json_file}.tmp"
  jq --argjson idx "$index" \
     --arg task "$task_name" \
     --arg outcome "$outcome" \
     --argjson dur "$duration_seconds" \
     --argjson cost "$cost" \
     --argjson must "$must_fix_count" \
     --argjson should "$should_fix_count" \
     --arg commit "$commit_sha" \
     --arg at "$(timestamp_iso)" \
     '.iterations += [{index: $idx, task: $task, outcome: $outcome, duration_seconds: $dur, cost_usd: $cost, must_fix_count: $must, should_fix_count: $should, commit: $commit, timestamp: $at}]' \
     "$json_file" > "$tmp" 2>/dev/null && mv "$tmp" "$json_file" || true
}
