# spec-loop

Spec-driven autonomous development loop powered by Claude Code.

Write a spec, then let `spec-loop` build it — task by task, with automated code review and fix cycles.

```
spec-loop v0.2.0

╭─ Spec ──────────────────────────────────────────╮
│                                                  │
│  user-auth                                       │
│  ████████░░░░░░░░ 3/7 done ◆ 4 remaining         │
│  feat/user-auth                                  │
│                                                  │
╰──────────────────────────────────────────────────╯

── Iteration 1 of 25 ─────────────────────────────

● build
    → Read     AGENTS.md
    → Write    src/api/routes/auth.ts
    → Bash     npm run lint && npm run typecheck
    ✓ result   45.2s ◆ $0.12

● review
    ✓ PASS     0 must-fix ◆ 0 should-fix

✓ Task 4 complete → 3 remaining
```

## How It Works

1. **`/spec-loop-spec`** — Create a feature spec with individual task files
2. **`spec-loop run`** — For each task: build → review → fix → commit
3. **`/spec-loop-status`** — Check progress at any time

The loop continues until all tasks are done, a task is blocked, or the circuit breaker trips (stagnation detection).

## Install

### CLI (recommended)

```bash
curl -sSf https://raw.githubusercontent.com/surajpatildev/spec-loop/main/install.sh | bash
hash -r
spec-loop version
```

Install target:

- binary: `~/.local/bin/spec-loop`
- runtime: native Rust binary

Notes:

- installer compiles from source using `cargo`
- first install may take ~30-90 seconds depending on machine/cache

### CLI (local development)

```bash
git clone https://github.com/surajpatildev/spec-loop.git
cd spec-loop
cargo check
./bin/spec-loop version
```

### Skills (Claude Code integration)

Install all repo skills into your project:

```bash
npx -y skills add surajpatildev/spec-loop --all -y
```

List available skills without installing:

```bash
npx -y skills add surajpatildev/spec-loop -l
```

This repo currently provides:

- `/spec-loop-spec` — Create feature specs for spec-loop
- `/spec-loop-status` — Show spec-loop progress

## Quick Start

```bash
# 1. Initialize in your project
spec-loop init

# 2. Edit AGENTS.md with your project's rules
#    (architecture, naming conventions, review checklist)

# 3. Create a spec (in Claude Code)
/spec-loop-spec Add user authentication with JWT tokens

# 4. Run the loop
spec-loop run
```

## Commands

```
spec-loop init                    Initialize in current project
spec-loop run [options]           Run build→review→fix loop
spec-loop status                  Show spec progress
spec-loop version                 Show version
spec-loop help                    Show help
```

### `spec-loop run` Options

| Flag | Description | Default |
|------|-------------|---------|
| `--spec <path>` | Spec directory | auto-detect |
| `--max-loops <n>` | Max iterations | 25 |
| `--max-review-fix-loops <n>` | Review-fix retries per task | 3 |
| `--max-tasks <n>` | Max tasks to complete in one run | unlimited |
| `--once` | Single build+review cycle | — |
| `--dry-run` | Print commands, don't execute | — |
| `--skip-review` | Build only, no review | — |
| `--resume` | Resume last session | — |
| `--verbose` | Full stream output | — |

## Configuration

`spec-loop init` creates `.speclooprc` with auto-detected settings:

```bash
# Project
PROJECT_TYPE="typescript"
VERIFY_COMMAND="npm run lint && npm run typecheck"
TEST_COMMAND="npm test"

# Claude Code
# CLAUDE_MODEL=""

# Loop limits
# MAX_LOOPS=25
# MAX_REVIEW_FIX_LOOPS=3
```

**Auto-detection** supports: TypeScript, JavaScript, Python, Rust, Go, Ruby, Java, Swift.

**Environment overrides:**

| Variable | Description |
|----------|-------------|
| `CLAUDE_BIN` | Claude Code binary (default: `claude`) |
| `CLAUDE_EXTRA_ARGS` | Extra args for claude command |
| `SPECLOOP_MAX_LOOPS` | Override max loops |
| `SPECLOOP_MAX_TASKS_PER_RUN` | Override max tasks per run |
| `SPECLOOP_SPECS_DIR` | Override specs directory |

## Project Structure

After `spec-loop init`:

```
your-project/
├── .speclooprc              # Project config
├── .agents/
│   ├── specs/               # Feature specs (created via /spec-loop-spec)
│   ├── templates/           # Spec/task templates (customizable)
│   ├── reference/           # Project patterns (you fill this)
│   └── decisions.md         # Design decisions log
├── .spec-loop/              # Runtime (gitignored)
│   └── sessions/            # Per-run logs
└── AGENTS.md                # Your project's rules
```

## Session Logs

Each run creates minimal, readable logs:

```
.spec-loop/sessions/20260227_143022_<spec-name>/
├── session.json     # Machine-readable analytics (cost, duration, exit reason)
├── session.md       # Iteration summaries
└── run.md           # Full run log (build/review/fix outputs by iteration)
```

`run.md` contains per-invocation and per-phase logs with both prompt and model output (plus Claude session IDs), while `session.json` keeps high-level telemetry.

When a run ends via `--once` or `--max-tasks`, the next invocation for the same spec continues the same session directory so logs stay in one place.

## Safety

- **Circuit breaker** — Stops after repeated iterations without spec/task progress
- **Session resume** — `--resume` picks up where the last run stopped
- **Dry run** — `--dry-run` to preview without calling Claude Code

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- Rust toolchain (`cargo`) for local build/install
- `git` recommended (optional)
- `tar` (used by installer)

## Troubleshooting

`spec-loop` not found after install:

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
spec-loop version
```

Cargo missing:

```bash
curl https://sh.rustup.rs -sSf | sh
```

Reinstall latest:

```bash
curl -sSf https://raw.githubusercontent.com/surajpatildev/spec-loop/main/install.sh | bash
hash -r
spec-loop version
```

## License

MIT
