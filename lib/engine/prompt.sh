#!/usr/bin/env bash
# spec-loop prompt generation — build, review, fix prompts

write_build_prompt() {
  local spec_dir="$1"
  local prompt_path="$2"

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="- Run the verify command before finishing: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="- Run tests before finishing: \`$TEST_COMMAND\`"
  fi

  local agents_context=""
  if [[ -f "AGENTS.md" ]]; then
    agents_context="\n## Project Rules\n\nRead and follow AGENTS.md in the project root."
  fi

  cat > "$prompt_path" <<PROMPT
You are implementing exactly ONE pending task from a feature spec.

## Spec

${spec_dir}

Read spec.md, progress.md (if present), and tasks in ${spec_dir}/tasks/.
${agents_context}

## Workflow

1. Identify the next eligible task (status \`pending\`, dependencies met).
2. Claim it by setting task status: \`pending -> in-progress\`.
3. Implement only the requested task scope (no unrelated refactors).
4. Run verification and tests.
${verify_section}
${test_section}
5. Update task documentation:
   - Fill **Done** checklist with specific evidence
   - Add concrete command output notes
   - Set status to \`in-review\` (not \`done\`)
6. Append one entry to progress.md if present.
7. Commit code changes with a specific message.
   - Use \`git add <specific files>\` only
   - Never stage spec files or progress.md

## Constraints

- Complete one task or report BLOCKED.
- Keep response concise and factual.
- Never mark a task \`done\` during build; review pass controls final completion.

## CRITICAL OUTPUT CONTRACT

Output EXACTLY one final status line as the very last line:

BUILD_STATUS: COMPLETED_TASK
BUILD_STATUS: BLOCKED
BUILD_STATUS: NO_PENDING_TASKS

Optional promise tags:
- If all tasks are complete: \`<promise>COMPLETE</promise>\` before final status
- If blocked: \`<promise>BLOCKED</promise>\` before final status

Formatting rules:
- Status lines must be plain text (not in code blocks, not indented, no backticks)
- The final BUILD_STATUS line must be the last line of the response
PROMPT
}

write_review_prompt() {
  local spec_dir="$1"
  local prompt_path="$2"
  local before_sha="${3:-}"

  local diff_instruction=""
  if [[ -n "$before_sha" ]]; then
    diff_instruction="Review ONLY this range: \`git diff ${before_sha}..HEAD\`."
  else
    diff_instruction="Review latest changes using \`git diff main...HEAD\` or \`git diff --staged\`."
  fi

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="- Run verify command: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="- Run test command: \`$TEST_COMMAND\`"
  fi

  cat > "$prompt_path" <<PROMPT
You are an independent reviewer. Verify, do not trust claims.

## Scope

${diff_instruction}
Spec: ${spec_dir}

## Checks

- Project conventions from AGENTS.md (if present)
- Task completeness and acceptance evidence
- No debug leftovers or commented-out code
- Reasonable structure and error handling
- Test evidence for meaningful logic changes
${verify_section}
${test_section}

If verify/test commands fail, treat as must-fix.

## Report format

Report:
- Must fix
- Should fix
- Suggestions

Then output the following 4 lines as the final lines:

REVIEW_STATUS: PASS
MUST_FIX_COUNT: 0
SHOULD_FIX_COUNT: 0
SUGGESTION_COUNT: 0

Use FAIL with real counts when issues exist.
If blocked, output \`<promise>BLOCKED</promise>\` before the status lines.

Formatting rules:
- Status lines must be plain text (not in code blocks, not indented, no backticks)
- The SUGGESTION_COUNT line must be the last line of the response
PROMPT
}

write_fix_prompt() {
  local spec_dir="$1"
  local review_excerpt="$2"
  local prompt_path="$3"

  local verify_section=""
  if [[ -n "$VERIFY_COMMAND" ]]; then
    verify_section="- Re-run verify command: \`$VERIFY_COMMAND\`"
  fi

  local test_section=""
  if [[ -n "$TEST_COMMAND" ]]; then
    test_section="- Re-run tests: \`$TEST_COMMAND\`"
  fi

  cat > "$prompt_path" <<PROMPT
You are fixing review findings from a failed review.

## Spec

${spec_dir}

## Findings to fix

${review_excerpt}

## Workflow

1. Fix all must-fix items.
2. Fix all should-fix items.
3. Keep scope narrow (no unrelated refactors).
4. Re-run verification.
${verify_section}
${test_section}
5. Commit changes with explicit file staging only.

## CRITICAL OUTPUT CONTRACT

Output one final status line as the very last line:

BUILD_STATUS: FIXES_APPLIED
BUILD_STATUS: BLOCKED

If blocked, output \`<promise>BLOCKED</promise>\` before final status.

Formatting rules:
- Status lines must be plain text (not in code blocks, not indented, no backticks)
- The final BUILD_STATUS line must be the last line of the response
PROMPT
}
