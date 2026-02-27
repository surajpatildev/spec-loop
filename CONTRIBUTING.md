# Contributing to spec-loop

## Development Setup

```bash
git clone https://github.com/specloop/spec-loop.git
cd spec-loop
```

The CLI is pure bash — no build step. Run directly:

```bash
./bin/spec-loop version
./bin/spec-loop help
```

## Testing

Test in a temp directory:

```bash
mkdir /tmp/test-project && cd /tmp/test-project
git init
/path/to/spec-loop/bin/spec-loop init --no-wizard
/path/to/spec-loop/bin/spec-loop run --dry-run --once
```

## Project Structure

```
bin/spec-loop          Entry point — sources lib, dispatches commands
lib/
├── core/              Constants, logging, args, config, utils
├── engine/            Runner, stream parser, prompts, output parser, main loop
├── safety/            Circuit breaker, rate limiter, session management
├── tasks/             Spec resolution, task state
├── setup/             Init wizard, preflight checks
└── ui/                Terminal detection, spinner, preview, status display
.agents/
├── skills/            4 SKILL.md files (spec, build, review, status)
└── templates/         Spec and task templates
```

## Conventions

- Shell scripts use `set -euo pipefail`
- Functions are lowercase with underscores
- Private functions prefixed with `_`
- Colors via `$C_*` variables, symbols via `$SYM_*`
- All output indented with 2+ spaces for the charm.sh aesthetic
- No `mapfile` (macOS bash 3.x compatibility)

## Pull Requests

1. Fork and create a feature branch
2. Test with `--dry-run` in a real project
3. Verify macOS + Linux compatibility (bash 3.2+)
4. Submit PR with description of changes
