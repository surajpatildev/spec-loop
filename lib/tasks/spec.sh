#!/usr/bin/env bash
# spec-loop task counting and spec resolution

count_active_tasks() {
  local spec_dir="$1"
  [[ -d "$spec_dir/tasks" ]] || { echo "0"; return; }

  local -a task_files=()
  shopt -s nullglob
  task_files=("$spec_dir"/tasks/*.md)
  shopt -u nullglob
  [[ ${#task_files[@]} -gt 0 ]] || { echo "0"; return; }

  awk '/^> Status: pending$|^> Status: in-progress$/ { count += 1 } END { print count + 0 }' "${task_files[@]}"
}

count_pending_tasks() {
  local spec_dir="$1"
  [[ -d "$spec_dir/tasks" ]] || { echo "0"; return; }

  local -a task_files=()
  shopt -s nullglob
  task_files=("$spec_dir"/tasks/*.md)
  shopt -u nullglob
  [[ ${#task_files[@]} -gt 0 ]] || { echo "0"; return; }

  awk '/^> Status: pending$/ { count += 1 } END { print count + 0 }' "${task_files[@]}"
}

count_done_tasks() {
  local spec_dir="$1"
  [[ -d "$spec_dir/tasks" ]] || { echo "0"; return; }

  local -a task_files=()
  shopt -s nullglob
  task_files=("$spec_dir"/tasks/*.md)
  shopt -u nullglob
  [[ ${#task_files[@]} -gt 0 ]] || { echo "0"; return; }

  awk '/^> Status: done$/ { count += 1 } END { print count + 0 }' "${task_files[@]}"
}

count_total_tasks() {
  local spec_dir="$1"
  [[ -d "$spec_dir/tasks" ]] || { echo "0"; return; }

  local -a task_files=()
  shopt -s nullglob
  task_files=("$spec_dir"/tasks/*.md)
  shopt -u nullglob

  echo "${#task_files[@]}"
}

resolve_spec_dir() {
  if [[ -n "$SPEC_ARG" ]]; then
    [[ -d "$SPEC_ARG" ]] || die "Spec directory does not exist: $SPEC_ARG"
    echo "$SPEC_ARG"
    return
  fi

  [[ -d "$SPECS_DIR" ]] || die "No specs directory found: $SPECS_DIR"

  local all_specs=()
  while IFS= read -r d; do
    all_specs+=("$d")
  done < <(find "$SPECS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  [[ ${#all_specs[@]} -gt 0 ]] || die "No spec directories found under $SPECS_DIR"

  local active_specs=()
  local spec
  for spec in "${all_specs[@]}"; do
    if [[ "$(count_active_tasks "$spec")" -gt 0 ]]; then
      active_specs+=("$spec")
    fi
  done

  if [[ ${#active_specs[@]} -eq 0 ]]; then
    die "No active specs found (no pending/in-progress tasks)"
  fi

  if [[ ${#active_specs[@]} -gt 1 ]]; then
    step_error "Multiple active specs detected. Pass --spec explicitly:"
    for spec in "${active_specs[@]}"; do
      step_info "  $spec"
    done
    exit 1
  fi

  echo "${active_specs[0]}"
}

get_spec_name() {
  local spec_dir="$1"
  basename "$spec_dir"
}
