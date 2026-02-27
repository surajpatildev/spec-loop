#!/usr/bin/env bash
# spec-loop uninstaller
set -euo pipefail

INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"

echo ""
echo "  Uninstalling spec-loop..."

if [[ -f "$BIN_DIR/spec-loop" ]]; then
  rm "$BIN_DIR/spec-loop"
  echo "  ✓ Removed $BIN_DIR/spec-loop"
fi

echo ""
echo "  ✓ spec-loop uninstalled"
echo ""
