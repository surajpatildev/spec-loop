# spec-loop Roadmap

## Done

- [x] Live elapsed timer — `[12s]` ticking in-place during each phase
- [x] Grouped Bash results — show stdout/pass/fail inline after Bash tool calls
- [x] Task name in iteration header — `── Iteration 1 ◆ Build system prompt ──`
- [x] Terminal bell on completion — `\a` when the loop finishes (any exit reason)
- [x] Simplified session logs — flat files, no subdirs, no raw NDJSON

## Next Up

### Parallel Tasks
Run independent tasks concurrently. Tasks 1, 2, 3 in a spec may have no dependencies on each other — detect this and spawn multiple Claude sessions in parallel.

- Detect parallel-eligible tasks (no `depends_on` or all deps met)
- Spawn N Claude sessions concurrently (with shared cost tracking)
- Interleave stream output with task labels
- Review each task's changes independently
- Requires careful git branch management (parallel branches, merge back)

### Interactive Mode
After review fails, show the findings and ask the user whether to auto-fix or manually intervene.

- Read from `/dev/tty` for user input (since stdin is occupied by the pipeline)
- Options: `[a]uto-fix`, `[s]kip`, `[q]uit`, `[m]anual` (pause loop, user fixes, resume)
- Show a compact summary of must-fix / should-fix counts before prompting

### Git Diff Preview
After build completes, show a compact `git diff --stat` so you see what files changed before review starts.

- Run `git diff --stat $before_sha..HEAD` after build phase
- Display as indented step lines: `→ src/prompt.ts | 42 ++++++`
- Only show if there are actual changes (skip if no diff)

### Cost Budget
`--budget 5.00` flag that stops the loop if cumulative cost exceeds the limit.

- Track `total_cost` against `BUDGET` threshold
- Check after each Claude invocation (build, review, fix)
- Exit with clear message: "Budget exceeded ($4.82 / $5.00). 2 tasks remaining."
- Add to `.speclooprc` as `BUDGET=` (optional)

### Webhook / Notification
POST to a URL when the loop completes, for Slack/Discord integration.

- `--webhook <url>` flag or `WEBHOOK_URL` in `.speclooprc`
- JSON payload: `{ spec, tasks_completed, cost, duration, exit_reason }`
- Fire on any exit (complete, blocked, circuit open, budget exceeded)
- Non-blocking (background curl, don't block loop exit)

### Session Replay
`spec-loop replay <session-dir>` that plays back the session log with timing.

- Read `session.json` for timing data
- Read `NN.md` files for content
- Replay terminal output with simulated delays
- `--speed 2x` for faster playback
- Good for demos and debugging
