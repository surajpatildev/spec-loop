#!/usr/bin/env bash
# spec-loop configuration — reads .speclooprc and merges with defaults

SPECLOOPRC=".speclooprc"

# Configuration values (set by load_config)
PROJECT_TYPE=""
VERIFY_COMMAND=""
TEST_COMMAND=""
CLAUDE_BIN="${CLAUDE_BIN:-$DEFAULT_CLAUDE_BIN}"
CLAUDE_MODEL=""
CLAUDE_EXTRA_ARGS="${CLAUDE_EXTRA_ARGS:-}"
SPECS_DIR="$DEFAULT_SPECS_DIR"
SESSION_DIR="$DEFAULT_SESSION_DIR"
SHOW_PREVIEW="true"
PREVIEW_LINES="$DEFAULT_PREVIEW_LINES"
USE_ICONS="true"
CB_NO_PROGRESS_THRESHOLD="$DEFAULT_CB_NO_PROGRESS_THRESHOLD"
CB_COOLDOWN_MINUTES="$DEFAULT_CB_COOLDOWN_MINUTES"

load_config() {
  # Save CLI-provided values so they can override config file + env vars.
  # CLI flags have highest priority: CLI > env > .speclooprc > defaults.
  local cli_max_loops="$MAX_LOOPS"
  local cli_max_review_fix_loops="$MAX_REVIEW_FIX_LOOPS"
  local cli_spec_arg="${SPEC_ARG:-}"

  if [[ -f "$SPECLOOPRC" ]]; then
    # Source the config file — it's bash-compatible
    # shellcheck disable=SC1090
    source "$SPECLOOPRC"
  fi

  # Environment overrides (over config file)
  [[ -n "${SPECLOOP_MAX_LOOPS:-}" ]] && MAX_LOOPS="$SPECLOOP_MAX_LOOPS"
  [[ -n "${SPECLOOP_MAX_REVIEW_FIX_LOOPS:-}" ]] && MAX_REVIEW_FIX_LOOPS="$SPECLOOP_MAX_REVIEW_FIX_LOOPS"
  [[ -n "${SPECLOOP_SPECS_DIR:-}" ]] && SPECS_DIR="$SPECLOOP_SPECS_DIR"
  [[ -n "${SPECLOOP_SESSION_DIR:-}" ]] && SESSION_DIR="$SPECLOOP_SESSION_DIR"

  # CLI flags override everything (only if user explicitly passed them)
  if [[ "$cli_max_loops" != "$DEFAULT_MAX_LOOPS" ]]; then
    MAX_LOOPS="$cli_max_loops"
  fi
  if [[ "$cli_max_review_fix_loops" != "$DEFAULT_MAX_REVIEW_FIX_LOOPS" ]]; then
    MAX_REVIEW_FIX_LOOPS="$cli_max_review_fix_loops"
  fi

  # Apply --once override (always wins)
  if [[ "$ONCE" == "true" ]]; then
    MAX_LOOPS=1
  fi
}

# Detect project type from files in current directory
detect_project_type() {
  if [[ -f "tsconfig.json" ]]; then
    echo "typescript"
  elif [[ -f "package.json" ]]; then
    echo "javascript"
  elif [[ -f "pyproject.toml" || -f "setup.py" || -f "setup.cfg" ]]; then
    echo "python"
  elif [[ -f "Cargo.toml" ]]; then
    echo "rust"
  elif [[ -f "go.mod" ]]; then
    echo "go"
  elif [[ -f "Gemfile" ]]; then
    echo "ruby"
  elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
    echo "java"
  elif [[ -f "Package.swift" ]]; then
    echo "swift"
  else
    echo "generic"
  fi
}

# Detect verify command based on project type
detect_verify_command() {
  local project_type="$1"
  case "$project_type" in
    typescript)
      if [[ -f "biome.json" ]]; then
        echo "npx biome check ."
      else
        echo "npm run lint && npm run typecheck"
      fi ;;
    javascript)
      echo "npm run lint" ;;
    python)
      if [[ -f "Makefile" ]] && grep -q 'check:' Makefile 2>/dev/null; then
        echo "make check"
      elif [[ -f "pyproject.toml" ]] && grep -q 'ruff' pyproject.toml 2>/dev/null; then
        echo "ruff check . && mypy ."
      else
        echo "python -m py_compile"
      fi ;;
    rust)
      echo "cargo clippy && cargo check" ;;
    go)
      echo "go vet ./..." ;;
    ruby)
      echo "bundle exec rubocop" ;;
    java)
      echo "./gradlew check" ;;
    swift)
      echo "swift build" ;;
    *)
      echo "" ;;
  esac
}

# Detect test command based on project type
detect_test_command() {
  local project_type="$1"
  case "$project_type" in
    typescript|javascript) echo "npm test" ;;
    python)
      if [[ -f "pyproject.toml" ]] && grep -q 'pytest' pyproject.toml 2>/dev/null; then
        echo "pytest"
      else
        echo "python -m pytest"
      fi ;;
    rust) echo "cargo test" ;;
    go) echo "go test ./..." ;;
    ruby) echo "bundle exec rspec" ;;
    java) echo "./gradlew test" ;;
    swift) echo "swift test" ;;
    *) echo "" ;;
  esac
}
