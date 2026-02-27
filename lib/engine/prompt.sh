#!/usr/bin/env bash
# spec-loop prompt generation — build, review, fix prompts
#
# CRITICAL: Slash commands (/build, /review) do NOT work in --print mode.
# All skill instructions must be inlined directly into the prompt.

# ── BUILD PROMPT ────────────────────────────────────

write_build_prompt() {
  local spec_dir="$1"
  local prompt_path="$2"

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="- Run the verify command after every significant edit: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="- Run tests after implementation: \`$TEST_COMMAND\`"
  fi

  # Read AGENTS.md content if it exists
  local agents_context=""
  if [[ -f "AGENTS.md" ]]; then
    agents_context="

## Project Rules (from AGENTS.md)

Read and follow AGENTS.md in the project root. It contains the project's architecture rules, naming conventions, and patterns."
  fi

  cat > "$prompt_path" <<PROMPT
You are implementing tasks from a feature spec. You work on exactly ONE task per invocation.

## Spec Location

${spec_dir}

Read the spec.md and all task files in ${spec_dir}/tasks/ to orient yourself.
${agents_context}

## Your Job

1. **Orient** — Read the spec, read progress.md (if it exists) for context on what's been done, identify the next eligible task (status: pending, dependencies met).

2. **Claim** — Update the task file status from \`pending\` to \`in-progress\`.

3. **Implement** — Build the task end-to-end:
   - Follow the task's "How" section and "Files" list
   - Follow patterns from the existing codebase
${verify_section}
${test_section}

4. **Self-Review** — Before committing, review your own changes:
   - Check every acceptance criterion in the task file
   - Ensure no debug code, no commented-out code, no hardcoded values
   - Run verify/test commands and fix any failures

5. **Document** — Update the task file:
   - Fill the "Done" checklist with specifics (not just checkmarks)
   - Add concrete verification evidence to "Notes" (commands run and key outputs)
   - Update status to \`done\`

6. **Log Progress** — If progress.md exists in the spec directory, append a log entry with timestamp and summary of what was done.

7. **Commit** — Stage ONLY source code changes and commit with a descriptive message. The commit message should reference the task number and name.
   - Use \`git add <specific files>\` — do NOT use \`git add .\` or \`git add -A\`
   - NEVER stage spec/task files (\`.agents/specs/\`) or progress.md — these are local development state
   - Only commit source code, tests, config files, and package files

## Constraints

- Pick exactly ONE task. Complete it fully or report BLOCKED.
- Do not skip acceptance criteria — every one must be verifiable.
- Include real evidence in Done/Notes, not just claims.
- Always commit your work when the task is complete and verified.
- NEVER commit files under \`.agents/specs/\` — they are gitignored and local-only.

## CRITICAL: Machine-Readable Output

Your response MUST end with exactly one of these status lines as the very last line of your response. This is required for the automation loop to continue. If you omit this line, the loop will fail.

\`\`\`
BUILD_STATUS: COMPLETED_TASK
BUILD_STATUS: BLOCKED
BUILD_STATUS: NO_PENDING_TASKS
\`\`\`

If ALL spec tasks are now done, also include on its own line before the BUILD_STATUS:
\`\`\`
<promise>COMPLETE</promise>
\`\`\`

If you are blocked by missing credentials/services/human decisions, include on its own line before the BUILD_STATUS:
\`\`\`
<promise>BLOCKED</promise>
\`\`\`

IMPORTANT: The very last line of your response must always be one of the BUILD_STATUS lines above. No text after it.
PROMPT
}

# ── REVIEW PROMPT ───────────────────────────────────

write_review_prompt() {
  local spec_dir="$1"
  local prompt_path="$2"
  local before_sha="${3:-}"

  local diff_range=""
  if [[ -n "$before_sha" ]]; then
    diff_range="${before_sha}..HEAD"
  fi

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="
- Run the verify command: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="
- Run the test command: \`$TEST_COMMAND\`"
  fi

  local diff_instruction=""
  if [[ -n "$diff_range" ]]; then
    diff_instruction="Review ONLY the changes in this diff range: \`git diff ${diff_range}\`

This is the scope of changes from the most recent build task. Do not review code outside this range."
  else
    diff_instruction="Review the latest changes: \`git diff main...HEAD\` or \`git diff --staged\`"
  fi

  local spec_section=""
  if [[ -n "$spec_dir" && -d "$spec_dir" ]]; then
    spec_section="
## Task Completeness

This build was part of spec: ${spec_dir}

1. Identify which task was just completed (check for status: done with recent changes)
2. Read that task file and verify:
   - Every **Acceptance** criterion has evidence of being met
   - The **Done** checklist is filled with specifics, not just checkmarks
   - **Notes** contain concrete verification evidence
   - A git commit was made (check \`git log -1 --oneline\`)
3. If progress.md exists, check it was updated"
  fi

  cat > "$prompt_path" <<PROMPT
You are an independent code reviewer. Trust nothing — verify everything.

## Scope

${diff_instruction}
${spec_section}

## Review Checklist

### Project Rules
Read AGENTS.md (if it exists) and use it as your review checklist. For every changed file, verify compliance with the project's conventions.

### Code Quality
- No commented-out code left behind
- No debug print/log statements
- Functions are single-responsibility
- Error messages are descriptive
- No duplicated logic that should be extracted
- No hardcoded values that should be configurable

### Test Evidence
- Were tests added or updated for the changes?
- Check \`git diff --stat\` — were test files actually created/modified?
- For significant logic changes without tests: flag as **Must Fix**
- Do NOT trust self-reported test results — check for test file changes

### Verify Tooling
${verify_section}${test_section}

If any command fails, flag as **Must Fix** with the error output.

## Independence Principle

- Do NOT trust claims of "tests pass" or "I verified it"
- You must check for evidence: command output, test file changes in the diff
- If no test evidence exists for meaningful changes: flag as **Must Fix**

## Report

Summarize findings in three categories:
- **Must fix**: Architecture violations, missing types, security issues, missing tests, failing verify/test commands, incomplete acceptance criteria
- **Should fix**: Style inconsistencies, missing logs, naming issues
- **Suggestions**: Optional improvements, performance, readability

## CRITICAL: Machine-Readable Output

Your response MUST end with these exact lines as the very last 4 lines. Replace \`PASS | FAIL\` with either PASS or FAIL, and \`<number>\` with actual numbers. This is required for the automation loop to continue.

\`\`\`
REVIEW_STATUS: PASS
MUST_FIX_COUNT: 0
SHOULD_FIX_COUNT: 0
SUGGESTION_COUNT: 0
\`\`\`

PASS only if MUST_FIX_COUNT is 0 AND SHOULD_FIX_COUNT is 0.

If review is blocked by missing context, include before the status lines:
\`\`\`
<promise>BLOCKED</promise>
\`\`\`

IMPORTANT: The very last lines of your response must always be the REVIEW_STATUS block above. No text after it.
PROMPT
}

# ── FIX PROMPT ──────────────────────────────────────

write_fix_prompt() {
  local spec_dir="$1"
  local iter_file="$2"
  local prompt_path="$3"

  # Extract the review section from the iteration .md file
  local review_excerpt=""
  if [[ -f "$iter_file" && -s "$iter_file" ]]; then
    # Get everything from "## Review" onward (the review output and any recheck)
    review_excerpt=$(sed -n '/^## Review/,$ p' "$iter_file" | head -250)
  fi

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="- Re-run the verify command after fixes: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="- Re-run tests after fixes: \`$TEST_COMMAND\`"
  fi

  cat > "$prompt_path" <<PROMPT
You are fixing review findings from a code review. Fix all issues — must-fix AND should-fix.

## Spec

${spec_dir}

## Review Findings

${review_excerpt}

## Your Job

1. Fix ALL must-fix findings
2. Fix ALL should-fix findings
3. For each fix, verify it doesn't break anything else
${verify_section}
${test_section}
4. Update task documentation if the fixes affect acceptance criteria or notes
5. Commit the fixes with a descriptive message using \`git add <specific files>\`
   - NEVER stage spec/task files (\`.agents/specs/\`) — they are local-only

## Constraints

- Only fix issues identified in the review — don't refactor unrelated code
- If a review finding is incorrect or not applicable, explain why in your response
- Ensure all verify/test commands pass after fixes
- NEVER commit files under \`.agents/specs/\` — they are gitignored and local-only

## CRITICAL: Machine-Readable Output

Your response MUST end with exactly one of these status lines as the very last line. This is required for the automation loop to continue.

\`\`\`
BUILD_STATUS: FIXES_APPLIED
BUILD_STATUS: BLOCKED
\`\`\`

If you are blocked, include before the BUILD_STATUS:
\`\`\`
<promise>BLOCKED</promise>
\`\`\`

IMPORTANT: The very last line of your response must always be one of the BUILD_STATUS lines above. No text after it.
PROMPT
}
