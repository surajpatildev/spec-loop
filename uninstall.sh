#!/usr/bin/env bash
# spec-loop uninstaller
set -euo pipefail

INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib/spec-loop"

echo ""
echo "  Uninstalling spec-loop..."

if [[ -f "$BIN_DIR/spec-loop" ]]; then
  rm -f "$BIN_DIR/spec-loop"
  echo "  ✓ Removed $BIN_DIR/spec-loop"
fi

if [[ -d "$LIB_DIR" ]]; then
  rm -rf "$LIB_DIR"
  echo "  ✓ Removed $LIB_DIR"
fi

echo ""
echo "  ✓ spec-loop uninstalled"
echo ""
echo "  Note: Project files (.speclooprc, .agents/, .spec-loop/) are not removed."
echo "  Remove them manually if desired."
echo ""
