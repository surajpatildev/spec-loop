#!/usr/bin/env bash
# spec-loop installer — builds Rust binary and installs to ~/.local/bin
set -euo pipefail

REPO="surajpatildev/spec-loop"
REF="${SPEC_LOOP_REF:-main}"
INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  DIM='\033[2m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' BLUE='' DIM='' BOLD='' RESET=''
fi

info() { echo -e "  ${BLUE}→${RESET} $*"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
die()  { echo -e "  ✗ $*" >&2; exit 1; }

echo ""
echo -e "  ${BOLD}spec-loop${RESET} installer"
echo ""

command -v cargo >/dev/null 2>&1 || die "cargo is required (https://rustup.rs)"
command -v tar >/dev/null 2>&1 || die "tar is required"

mkdir -p "$BIN_DIR"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info "Downloading spec-loop..."
if command -v curl >/dev/null 2>&1; then
  if curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" -o "$TEMP_DIR/repo.tar.gz"; then
    tar -xzf "$TEMP_DIR/repo.tar.gz" -C "$TEMP_DIR" --strip-components=1 || die "Failed to extract archive"
    ok "Downloaded"
  else
    die "Failed to download repository archive"
  fi
elif command -v git >/dev/null 2>&1; then
  git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TEMP_DIR" >/dev/null 2>&1 || die "Failed to clone repository"
  ok "Downloaded"
else
  die "Need either curl or git to download repository"
fi

info "Building Rust binary..."
BUILD_LOG="$TEMP_DIR/build.log"
if ! (
  cd "$TEMP_DIR"
  cargo build --release --bin spec-loop --quiet >"$BUILD_LOG" 2>&1
); then
  echo ""
  echo "  Build failed. Last 40 log lines:"
  tail -n 40 "$BUILD_LOG" || true
  exit 1
fi
ok "Built"

info "Installing to $INSTALL_DIR..."
# If an older symlink exists (common in local-dev setups), remove it first so
# we don't overwrite the symlink target.
rm -f "$BIN_DIR/spec-loop"
install -m 755 "$TEMP_DIR/target/release/spec-loop" "$BIN_DIR/spec-loop"

ok "Installed spec-loop binary"
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
