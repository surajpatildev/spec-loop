#!/usr/bin/env bash
# spec-loop CLI argument parsing

# ── Global state set by parse_run_args ──────────────
SPEC_ARG=""
MAX_LOOPS="$DEFAULT_MAX_LOOPS"
MAX_REVIEW_FIX_LOOPS="$DEFAULT_MAX_REVIEW_FIX_LOOPS"
ONCE="false"
DRY_RUN="false"
SKIP_REVIEW="false"
RESUME="false"
VERBOSE="false"

# ── Global state set by parse_init_args ─────────────
INIT_FORCE="false"
INIT_NO_WIZARD="false"
INIT_VERIFY_CMD=""
INIT_TEST_CMD=""

usage() {
  cat <<'EOF'

  spec-loop — spec-driven autonomous development loop

  Usage:
    spec-loop <command> [options]

  Commands:
    init       Initialize spec-loop in the current project
    run        Run the build→review→fix loop
    status     Show current spec progress
    version    Show version
    help       Show this help

  Run 'spec-loop <command> --help' for command-specific options.

EOF
}

usage_run() {
  cat <<'EOF'

  spec-loop run [options]

  Options:
    --spec <path>              Spec directory (auto-detects if one active)
    --max-loops <n>            Max task iterations (default: 25)
    --max-review-fix-loops <n> Review-fix retries per task (default: 3)
    --once                     Single build+review cycle
    --dry-run                  Print commands without executing
    --skip-review              Build only, no review phase
    --resume                   Resume last session
    --verbose                  Show full stream output
    -h, --help                 Show this help

  Environment:
    CLAUDE_BIN                 Claude Code binary (default: claude)
    CLAUDE_EXTRA_ARGS          Extra args for the claude command

EOF
}

usage_init() {
  cat <<'EOF'

  spec-loop init [options]

  Options:
    --force                    Overwrite existing configuration
    --no-wizard                Non-interactive (use detection + defaults)
    --verify-cmd <cmd>         Override detected verify command
    --test-cmd <cmd>           Override detected test command
    -h, --help                 Show this help

EOF
}

parse_run_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --spec)
        [[ $# -ge 2 ]] || die "--spec requires a value"
        SPEC_ARG="$2"; shift 2 ;;
      --max-loops)
        [[ $# -ge 2 ]] || die "--max-loops requires a value"
        MAX_LOOPS="$2"; shift 2 ;;
      --max-review-fix-loops)
        [[ $# -ge 2 ]] || die "--max-review-fix-loops requires a value"
        MAX_REVIEW_FIX_LOOPS="$2"; shift 2 ;;
      --once)
        ONCE="true"; shift ;;
      --dry-run)
        DRY_RUN="true"; shift ;;
      --skip-review)
        SKIP_REVIEW="true"; shift ;;
      --resume)
        RESUME="true"; shift ;;
      --verbose)
        VERBOSE="true"; shift ;;
      -h|--help)
        usage_run; exit 0 ;;
      *)
        die "Unknown argument: $1" ;;
    esac
  done
}

parse_init_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        INIT_FORCE="true"; shift ;;
      --no-wizard)
        INIT_NO_WIZARD="true"; shift ;;
      --verify-cmd)
        [[ $# -ge 2 ]] || die "--verify-cmd requires a value"
        INIT_VERIFY_CMD="$2"; shift 2 ;;
      --test-cmd)
        [[ $# -ge 2 ]] || die "--test-cmd requires a value"
        INIT_TEST_CMD="$2"; shift 2 ;;
      -h|--help)
        usage_init; exit 0 ;;
      *)
        die "Unknown argument: $1" ;;
    esac
  done
}
