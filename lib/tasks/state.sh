#!/usr/bin/env bash
# spec-loop task state — read/update task status

# Get the status string from a task file
get_task_status() {
  local task_file="$1"
  awk '
    /^[[:space:]]*>?[[:space:]]*Status:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*>?[[:space:]]*Status:[[:space:]]*/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      print tolower(line)
      exit
    }
  ' "$task_file"
}

# Get the task name from the first heading
get_task_name() {
  local task_file="$1"
  awk '/^# / { sub(/^# /, ""); print; exit }' "$task_file"
}

# List task files in order
list_task_files() {
  local spec_dir="$1"
  [[ -d "$spec_dir/tasks" ]] || return

  shopt -s nullglob
  local -a files=("$spec_dir"/tasks/*.md)
  shopt -u nullglob

  printf '%s\n' "${files[@]}"
}

# Find next eligible task (pending, deps met)
find_next_task() {
  local spec_dir="$1"
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local status
    status=$(get_task_status "$file")
    if [[ "$status" == "pending" ]]; then
      echo "$file"
      return
    fi
  done < <(list_task_files "$spec_dir")
}

find_open_task() {
  local spec_dir="$1"
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local status
    status=$(get_task_status "$file")
    if [[ "$status" == "pending" || "$status" == "in-progress" || "$status" == "in-review" ]]; then
      echo "$file"
      return
    fi
  done < <(list_task_files "$spec_dir")
}

set_task_status() {
  local task_file="$1"
  local new_status="$2"

  [[ -f "$task_file" ]] || return 1
  sed -E -i.bak \
    -e "s/^[[:space:]]*>[[:space:]]*Status:[[:space:]]*.*/> Status: ${new_status}/" \
    -e "s/^[[:space:]]*Status:[[:space:]]*.*/Status: ${new_status}/" \
    "$task_file" && rm -f "${task_file}.bak"
}
