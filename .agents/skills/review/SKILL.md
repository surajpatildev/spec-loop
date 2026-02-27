---
name: review
description: Review code changes for correctness, completeness, and quality. Use after implementation to verify work before merging.
---

# Review

Review code changes for correctness, completeness, and quality. Independent verification — trust nothing, check everything.

## Input

When invoked by spec-loop, you receive:
- `DIFF_RANGE` — the git range to review (e.g., `abc123..HEAD`)
- `SPEC_DIR` — the spec directory (if running against a spec)
- `VERIFY_COMMAND` — the project's lint/typecheck command
- `TEST_COMMAND` — the project's test command

When invoked standalone, review staged or recent changes.

## Workflow

### 0. Independence Principle

You are an independent verifier. Before reviewing:
- Do NOT trust claims of "tests pass" or "I verified it"
- Check for evidence: command output in task notes, test file changes in the diff
- If no evidence exists for meaningful changes: flag as **Must Fix**

### 1. Gather Changes

Determine what to review:
- If `DIFF_RANGE` is provided: `git diff $DIFF_RANGE`
- If reviewing staged: `git diff --staged`
- If reviewing a branch: `git diff main...HEAD`
- Identify all changed files and categorize by module/area

### 2. Project Rules Check

Read `AGENTS.md` (if it exists) and use it as your review checklist. The project's own rules define what's correct. For every changed file, verify compliance with whatever conventions the project defines.

If no `AGENTS.md` exists, review against standard software engineering practices.

### 3. Task Completeness (spec-loop mode)

If a `SPEC_DIR` is provided, verify the task that was just built:
- Read the task file that was claimed as completed
- Check every item in the **Acceptance** criteria — is there evidence each one is met?
- Check the **Done** checklist — is it filled with specifics, not just checkmarks?
- If `progress.md` exists in the spec, was it updated?
- Were any new decisions documented (if applicable)?
- Was a git commit made? Check `git log -1 --oneline`

### 4. Code Quality

For all changed files:
- [ ] No commented-out code left behind
- [ ] No debug print/log statements
- [ ] Functions are single-responsibility
- [ ] Error messages are descriptive
- [ ] No duplicated logic that should be extracted
- [ ] No hardcoded values that should be configurable

### 5. Test Evidence

- Were tests added or updated for the changes?
- Check `git diff --stat` — were test files actually created/modified?
- For significant logic changes without tests: flag as **Must Fix**
- **Do not trust self-reported test results** — check for actual test file changes

### 6. Verify Tooling

Run the project's verify and test commands if provided:
```bash
# VERIFY_COMMAND — lint, typecheck, format check
# TEST_COMMAND — test suite
```

If the commands fail, flag as **Must Fix** with the error output.

### 7. Report

Summarize findings in three categories:
- **Must fix**: Architecture violations, missing types, security issues, missing tests for significant changes, failing verify/test commands, incomplete acceptance criteria
- **Should fix**: Style inconsistencies, missing logs, naming issues
- **Suggestions**: Optional improvements, performance, readability

**End with machine-readable markers:**

```
REVIEW_STATUS: PASS | FAIL
MUST_FIX_COUNT: <number>
SHOULD_FIX_COUNT: <number>
SUGGESTION_COUNT: <number>
```

PASS only if MUST_FIX_COUNT is 0 AND SHOULD_FIX_COUNT is 0.

If review is blocked by missing context:
```
<promise>BLOCKED</promise>
```

## Rules

- Be specific — cite file paths and line numbers
- Don't nitpick formatting if the verify command passes
- If `AGENTS.md` exists, defer to it over general preferences
- If everything looks good, say so — don't invent issues
- Review ONLY the changes in scope (the diff), not the entire codebase
