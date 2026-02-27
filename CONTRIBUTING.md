# Contributing to spec-loop

## Development Setup

```bash
git clone https://github.com/specloop/spec-loop.git
cd spec-loop
cargo check
```

Run the CLI from repo root:

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
CLAUDE_BIN=true /path/to/spec-loop/bin/spec-loop run --dry-run --once
```

## Project Structure

```
bin/spec-loop          Rust CLI launcher
src/                   Rust runtime (commands, engine, session/logging, prompts)
.agents/
├── skills/            Namespaced skills (spec-loop-spec, spec-loop-status)
└── templates/         Spec and task templates
```

## Pull Requests

1. Create a feature branch
2. Run `cargo check` and `cargo test`
3. Smoke test with `--dry-run` in a real git project
4. Submit PR with a clear summary
