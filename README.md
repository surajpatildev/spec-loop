# spec-loop

Spec-driven autonomous development loop powered by Claude Code.

Write a spec, then let `spec-loop` build it — task by task, with automated code review and fix cycles.

```
spec-loop v0.1.0

╭─ Spec ──────────────────────────────────────────╮
│                                                  │
│  user-auth                                       │
│  ████████░░░░░░░░ 3/7 done ◆ 4 pending           │
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

1. **`/spec`** — Create a feature spec with individual task files
2. **`spec-loop run`** — For each task: build → review → fix → commit
3. **`/status`** — Check progress at any time

The loop continues until all tasks are done, a task is blocked, or the circuit breaker trips (stagnation detection).

## Install

### Skills (Claude Code integration)

```bash
npx skills add specloop/spec-loop
```

Installs 4 skills to `~/.agents/skills/` with symlinks to `~/.claude/skills/`:
- `/spec` — Create feature specs
- `/build` — Implement code with quality gates
- `/review` — Review changes against AGENTS.md rules
- `/status` — Show progress

### CLI (the automation loop)

```bash
curl -sSf https://raw.githubusercontent.com/specloop/spec-loop/main/install.sh | bash
```

Or via npm:

```bash
npm install -g @specloop/cli
```

## Quick Start

```bash
# 1. Initialize in your project
spec-loop init

# 2. Edit AGENTS.md with your project's rules
#    (architecture, naming conventions, review checklist)

# 3. Create a spec (in Claude Code)
/spec Add user authentication with JWT tokens

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
| `SPECLOOP_SPECS_DIR` | Override specs directory |

## Project Structure

After `spec-loop init`:

```
your-project/
├── .speclooprc              # Project config
├── .agents/
│   ├── specs/               # Feature specs (created via /spec)
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
.spec-loop/sessions/20260227_143022/
├── session.json     # Machine-readable analytics (cost, duration, exit reason)
├── session.md       # Human-readable summary (one entry per iteration)
├── 01.md            # Iteration 1 — build output, review output
└── 02.md            # Iteration 2 — build, review, fix, recheck (if needed)
```

Each iteration `.md` contains the full Claude response text organized by phase (Build, Review, Fix). No raw NDJSON logs or separate prompt files — just clean, readable output.

## Safety

- **Circuit breaker** — Stops after N iterations without git commits (stagnation detection)
- **Rate limiter** — Backs off when Claude Code rate limits are hit
- **Session resume** — `--resume` picks up where the last run stopped
- **Dry run** — `--dry-run` to preview without calling Claude Code

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- `jq` for JSON parsing
- `git` for version control
- Bash 3.2+ (macOS default works)

## License

MIT
