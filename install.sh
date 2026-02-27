#!/usr/bin/env bash
# spec-loop installer — installs the CLI binary and lib to ~/.local
set -euo pipefail

REPO="specloop/spec-loop"
INSTALL_DIR="${SPEC_LOOP_INSTALL_DIR:-$HOME/.local}"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib/spec-loop"

# Colors
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

# Check dependencies
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq / apt install jq)"

# Create directories
mkdir -p "$BIN_DIR" "$LIB_DIR"

# Clone or update
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info "Downloading spec-loop..."
if git clone --depth 1 "https://github.com/$REPO.git" "$TEMP_DIR" 2>/dev/null; then
  ok "Downloaded"
else
  die "Failed to clone repository. Check your internet connection."
fi

# Copy lib
info "Installing to $INSTALL_DIR..."
rm -rf "$LIB_DIR"
cp -R "$TEMP_DIR/lib" "$LIB_DIR/lib"
cp -R "$TEMP_DIR/.agents" "$LIB_DIR/.agents"

# Create bin wrapper that points to installed lib
cat > "$BIN_DIR/spec-loop" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$LIB_DIR"
LIB_DIR="\$SCRIPT_DIR/lib"
source "\${LIB_DIR}/core/constants.sh"
source "\${LIB_DIR}/core/utils.sh"
source "\${LIB_DIR}/core/logging.sh"
source "\${LIB_DIR}/core/args.sh"
source "\${LIB_DIR}/core/config.sh"
for module in \\
  "\${LIB_DIR}/setup/init.sh" \\
  "\${LIB_DIR}/setup/preflight.sh" \\
  "\${LIB_DIR}/tasks/spec.sh" \\
  "\${LIB_DIR}/tasks/state.sh" \\
  "\${LIB_DIR}/engine/runner.sh" \\
  "\${LIB_DIR}/engine/stream.sh" \\
  "\${LIB_DIR}/engine/prompt.sh" \\
  "\${LIB_DIR}/engine/parser.sh" \\
  "\${LIB_DIR}/engine/loop.sh" \\
  "\${LIB_DIR}/safety/circuit_breaker.sh" \\
  "\${LIB_DIR}/safety/rate_limiter.sh" \\
  "\${LIB_DIR}/safety/session.sh" \\
  "\${LIB_DIR}/ui/terminal.sh" \\
  "\${LIB_DIR}/ui/spinner.sh" \\
  "\${LIB_DIR}/ui/preview.sh" \\
  "\${LIB_DIR}/ui/display.sh"; do
  [[ -f "\$module" ]] && source "\$module"
done
cmd="\${1:-help}"
shift || true
case "\$cmd" in
  init) parse_init_args "\$@"; cmd_init ;;
  run) parse_run_args "\$@"; load_config; cmd_run ;;
  status) load_config; cmd_status ;;
  version|-v|--version) echo "spec-loop v\${SPECLOOP_VERSION}" ;;
  help|-h|--help) usage ;;
  *) die "Unknown command: \$cmd" ;;
esac
WRAPPER

chmod +x "$BIN_DIR/spec-loop"
ok "Installed spec-loop binary"

# Check PATH
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
