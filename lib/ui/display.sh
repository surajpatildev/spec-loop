#!/usr/bin/env bash
# spec-loop display — status command output

cmd_status() {
  print_header

  local specs_dir="$SPECS_DIR"
  if [[ ! -d "$specs_dir" ]]; then
    echo ""
    step_info "No specs directory found. Run 'spec-loop init' first."
    return
  fi

  local found_active="false"
  local spec_dir

  # Find all spec directories
  local all_specs=()
  while IFS= read -r d; do
    all_specs+=("$d")
  done < <(command find "$specs_dir" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ ${#all_specs[@]} -eq 0 ]]; then
    echo ""
    step_info "No specs found. Use /spec-loop-spec to create a feature spec."
    return
  fi

  for spec_dir in "${all_specs[@]}"; do
    local name total done_count remaining active_count
    name=$(basename "$spec_dir")
    total=$(count_total_tasks "$spec_dir")
    done_count=$(count_done_tasks "$spec_dir")
    remaining=$(count_remaining_tasks "$spec_dir")
    active_count=$(count_active_tasks "$spec_dir")

    if [[ "$active_count" -gt 0 ]]; then
      found_active="true"
      echo ""
      box_header "$name" 52
      box_empty
      box_line "  $(progress_bar "$done_count" "$total" 16 "done") ${SYM_DIAMOND} ${remaining} remaining"

      # Show current branch
      local branch
      branch="$(get_current_branch)"
      box_line "  ${C_DIM}${branch}${C_RESET}"

      # Next eligible task
      local next_task
      next_task=$(find_next_task "$spec_dir")
      if [[ -n "$next_task" ]]; then
        local task_name
        task_name=$(get_task_name "$next_task")
        box_line "  ${SYM_ARROW} Next: ${task_name}"
      fi

      box_empty
      box_footer
    fi
  done

  # Recent commits
  if is_git_repo && git rev-parse HEAD >/dev/null 2>&1; then
    echo ""
    echo -e "  ${C_DIM}Recent commits${C_RESET}"
    git log --oneline -5 2>/dev/null | while IFS= read -r line; do
      echo -e "  ${C_DIM}  ${line}${C_RESET}"
    done
  fi

  if [[ "$found_active" == "false" ]]; then
    echo ""
    step_info "No active specs (all tasks done or none created)."
    step_info "Use /spec-loop-spec to create a new feature spec."
  fi

  echo ""
}
