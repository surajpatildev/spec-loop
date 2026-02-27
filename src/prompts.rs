use std::path::Path;

use crate::config::Config;

pub fn build_prompt(spec_dir: &Path, cfg: &Config) -> String {
    let verify_section = if cfg.verify_command.is_empty() {
        String::new()
    } else {
        format!(
            "- Run the verify command before finishing: `{}`",
            cfg.verify_command
        )
    };

    let test_section = if cfg.test_command.is_empty() {
        String::new()
    } else {
        format!("- Run tests before finishing: `{}`", cfg.test_command)
    };

    let agents_context = if Path::new("AGENTS.md").exists() {
        "\n## Project Rules\n\nRead and follow AGENTS.md in the project root.".to_string()
    } else {
        String::new()
    };

    format!(
        "You are implementing exactly ONE pending task from a feature spec.\n\n## Spec\n\n{}\n\nRead spec.md, progress.md (if present), and tasks in {}/tasks/.{}\n\n## Workflow\n\n1. Identify the next eligible task (status `pending`, dependencies met).\n2. Claim it by setting task status: `pending -> in-progress`.\n3. Implement only the requested task scope (no unrelated refactors).\n4. Run verification and tests.\n{}\n{}\n5. Update task documentation:\n   - Fill **Done** checklist with specific evidence\n   - Add concrete command output notes\n   - Set status to `in-review` (not `done`)\n6. Append one entry to progress.md if present.\n7. If git is available, commit code changes with a specific message.\n   - Use `git add <specific files>` only\n   - Never stage spec files or progress.md\n\n## Constraints\n\n- Complete one task or report BLOCKED.\n- Keep response concise and factual.\n- Never mark a task `done` during build; review pass controls final completion.\n\n## CRITICAL OUTPUT CONTRACT\n\nOutput EXACTLY one final status line as the very last line:\n\nBUILD_STATUS: COMPLETED_TASK\nBUILD_STATUS: BLOCKED\nBUILD_STATUS: NO_PENDING_TASKS\n\nOptional promise tags:\n- If all tasks are complete: `<promise>COMPLETE</promise>` before final status\n- If blocked: `<promise>BLOCKED</promise>` before final status\n\nFormatting rules:\n- Status lines must be plain text (not in code blocks, not indented, no backticks)\n- The final BUILD_STATUS line must be the last line of the response\n",
        spec_dir.display(),
        spec_dir.display(),
        agents_context,
        verify_section,
        test_section,
    )
}

pub fn review_prompt(spec_dir: &Path, cfg: &Config, before_sha: Option<&str>) -> String {
    let diff_instruction = if let Some(sha) = before_sha.filter(|s| !s.is_empty()) {
        format!("Review ONLY this range: `git diff {}..HEAD`.", sha)
    } else {
        "Review latest changes using `git diff main...HEAD` or `git diff --staged`.".to_string()
    };

    let verify_section = if cfg.verify_command.is_empty() {
        String::new()
    } else {
        format!("- Run verify command: `{}`", cfg.verify_command)
    };

    let test_section = if cfg.test_command.is_empty() {
        String::new()
    } else {
        format!("- Run test command: `{}`", cfg.test_command)
    };

    format!(
        "You are an independent reviewer. Verify, do not trust claims.\n\n## Scope\n\n{}\nSpec: {}\n\n## Checks\n\n- Project conventions from AGENTS.md (if present)\n- Task completeness and acceptance evidence\n- No debug leftovers or commented-out code\n- Reasonable structure and error handling\n- Test evidence for meaningful logic changes\n{}\n{}\n\nIf verify/test commands fail, treat as must-fix.\n\n## Report format\n\nReport:\n- Must fix\n- Should fix\n- Suggestions\n\nThen output the following 4 lines as the final lines:\n\nREVIEW_STATUS: PASS\nMUST_FIX_COUNT: 0\nSHOULD_FIX_COUNT: 0\nSUGGESTION_COUNT: 0\n\nUse FAIL with real counts when issues exist.\nIf blocked, output `<promise>BLOCKED</promise>` before the status lines.\n\nFormatting rules:\n- Status lines must be plain text (not in code blocks, not indented, no backticks)\n- The SUGGESTION_COUNT line must be the last line of the response\n",
        diff_instruction,
        spec_dir.display(),
        verify_section,
        test_section,
    )
}

pub fn fix_prompt(spec_dir: &Path, cfg: &Config, review_excerpt: &str) -> String {
    let verify_section = if cfg.verify_command.is_empty() {
        String::new()
    } else {
        format!("- Re-run verify command: `{}`", cfg.verify_command)
    };

    let test_section = if cfg.test_command.is_empty() {
        String::new()
    } else {
        format!("- Re-run tests: `{}`", cfg.test_command)
    };

    format!(
        "You are fixing review findings from a failed review.\n\n## Spec\n\n{}\n\n## Findings to fix\n\n{}\n\n## Workflow\n\n1. Fix all must-fix items.\n2. Fix all should-fix items.\n3. Keep scope narrow (no unrelated refactors).\n4. Re-run verification.\n{}\n{}\n5. If git is available, commit changes with explicit file staging only.\n\n## CRITICAL OUTPUT CONTRACT\n\nOutput one final status line as the very last line:\n\nBUILD_STATUS: FIXES_APPLIED\nBUILD_STATUS: BLOCKED\n\nIf blocked, output `<promise>BLOCKED</promise>` before final status.\n\nFormatting rules:\n- Status lines must be plain text (not in code blocks, not indented, no backticks)\n- The final BUILD_STATUS line must be the last line of the response\n",
        spec_dir.display(),
        review_excerpt,
        verify_section,
        test_section,
    )
}
