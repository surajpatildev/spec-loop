#!/usr/bin/env bash
# spec-loop installer — builds Rust binary and installs to ~/.local/bin
set -euo pipefail

REPO="specloop/spec-loop"
INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib/spec-loop"

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

command -v git >/dev/null 2>&1 || die "git is required"
command -v cargo >/dev/null 2>&1 || die "cargo is required (https://rustup.rs)"

mkdir -p "$BIN_DIR" "$LIB_DIR"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info "Downloading spec-loop..."
git clone --depth 1 "https://github.com/$REPO.git" "$TEMP_DIR" >/dev/null 2>&1 || die "Failed to clone repository"
ok "Downloaded"

info "Building Rust binary..."
(
  cd "$TEMP_DIR"
  cargo build --release --bin spec-loop >/dev/null
)
ok "Built"

info "Installing to $INSTALL_DIR..."
cp "$TEMP_DIR/target/release/spec-loop" "$BIN_DIR/spec-loop"
chmod +x "$BIN_DIR/spec-loop"

# Keep bundled skills/templates for convenience
rm -rf "$LIB_DIR/.agents"
cp -R "$TEMP_DIR/.agents" "$LIB_DIR/.agents"
ok "Installed spec-loop binary"

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
