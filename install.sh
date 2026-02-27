#!/usr/bin/env bash
# spec-loop installer — installs spec-loop to ~/.local/bin
set -euo pipefail

REPO="surajpatildev/spec-loop"
REF="${SPEC_LOOP_REF:-main}"
INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"
BUILD_LOG=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  DIM='\033[2m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' BLUE='' CYAN='' DIM='' BOLD='' RESET=''
fi

info() { echo -e "  ${BLUE}→${RESET} $*"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
die()  { echo -e "  ✗ $*" >&2; exit 1; }

run_step() {
  local message="$1"; shift
  local log_file="$TEMP_DIR/${message//[^a-zA-Z0-9]/_}.log"
  local start_ts elapsed spinner_idx pid
  local -a spinner=( '-' '\\' '|' '/' )
  BUILD_LOG="$log_file"

  if [[ -t 1 ]]; then
    "$@" >"$log_file" 2>&1 &
    pid=$!
    start_ts=$(date +%s)
    spinner_idx=0
    while kill -0 "$pid" 2>/dev/null; do
      elapsed=$(( $(date +%s) - start_ts ))
      printf "\r  ${CYAN}%s${RESET} %s ${DIM}%02ds${RESET}" "${spinner[$spinner_idx]}" "$message" "$elapsed"
      spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
      sleep 0.1
    done

    if wait "$pid"; then
      printf "\r  ${GREEN}✓${RESET} %s%*s\n" "$message" 16 ""
      return 0
    fi

    printf "\r  ✗ %s%*s\n" "$message" 16 "" >&2
  else
    info "$message"
    if "$@" >"$log_file" 2>&1; then
      ok "$message"
      return 0
    fi
    echo "  ✗ $message" >&2
  fi

  echo "" >&2
  echo "  Last 40 log lines:" >&2
  tail -n 40 "$log_file" >&2 || true
  return 1
}

download_source() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" -o "$TEMP_DIR/repo.tar.gz"
    tar -xzf "$TEMP_DIR/repo.tar.gz" -C "$TEMP_DIR" --strip-components=1
  elif command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TEMP_DIR"
  else
    die "Need either curl or git to download repository"
  fi
}

build_binary() {
  (
    cd "$TEMP_DIR"
    cargo build --release --bin spec-loop --quiet
  )
}

install_binary() {
  rm -f "$BIN_DIR/spec-loop"
  install -m 755 "$TEMP_DIR/target/release/spec-loop" "$BIN_DIR/spec-loop"
}

echo ""
echo -e "  ${BOLD}spec-loop${RESET} installer"
echo ""

command -v cargo >/dev/null 2>&1 || die "Required toolchain is missing. See README install prerequisites."
command -v tar >/dev/null 2>&1 || die "tar is required"

mkdir -p "$BIN_DIR"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

run_step "Downloading" download_source
run_step "Installing" build_binary
run_step "Finalizing" install_binary

ok "Installed spec-loop"
ok "Version: $("$BIN_DIR/spec-loop" version 2>/dev/null || echo unknown)"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  info "Add to your shell profile:"
  echo -e "    ${DIM}export PATH=\"$BIN_DIR:\$PATH\"${RESET}"
fi

echo ""
ok "${BOLD}Installation complete${RESET}"
echo ""
info "Run: spec-loop init"
echo ""
