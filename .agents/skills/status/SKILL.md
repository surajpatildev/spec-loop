---
name: status
description: Show current progress and orientation. Use after compaction, new session, or to check where things stand.
---

# Status

Quick orientation. Answers: "Where are we?" Reads state from files — works after compaction, new sessions, or when picking up someone else's work.

## Workflow

### 1. Check for Active Specs

Look in `.agents/specs/` for directories containing task files with `Status: pending` or `Status: in-progress`.

### 2. For Each Active Spec

- Read all task files → count by status (done / in-progress / pending / blocked)
- Identify next eligible task (pending, deps met)
- If `progress.md` exists, read the last 3 log entries

### 3. Check Git State

- Run `git log --oneline -5` for recent commits
- Run `git branch --show-current` to show current branch

### 4. Report

```
## Active: <spec-name>
Branch: <current branch name>
Tasks: N/M done | N in-progress | N pending | N blocked
Next: Task N — <name> (depends on: N, N)

### Recent Progress
[YYYY-MM-DD HH:MM] Task N: <Name> — <summary>

## Recent Commits
abc1234 <message>
def5678 <message>
```

If no active specs, report:
```
No active specs. Recent commits shown below.
Use `/spec` to create a new feature spec, or run `spec-loop run` for standalone work.
```

## Rules

- Read-only — never modify any files
- Show all active specs, not just the first one found
- If a task is in-progress with no recent commits, flag it: "Task N: in-progress (possibly stale — no commits since YYYY-MM-DD)"
