use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

use anyhow::{bail, Context, Result};

use crate::circuit_breaker::CircuitBreaker;
use crate::claude::{has_tag, parse_kv, run_claude};
use crate::cli::{InitArgs, RunArgs};
use crate::config::{
    detect_project_type, detect_test_command, detect_verify_command, load_config, Config,
    DEFAULT_MAX_LOOPS, DEFAULT_MAX_REVIEW_FIX_LOOPS,
};
use crate::constants::{
    EXIT_BLOCKED, EXIT_CIRCUIT_OPEN, EXIT_MAX_ITERATIONS, EXIT_OK, SPECLOOP_VERSION,
};
use crate::prompts::{build_prompt, fix_prompt, review_prompt};
use crate::session::{
    append_iteration_log, append_run_invocation_header, append_run_iteration_header,
    append_run_phase, clear_resume_state, ensure_session_initialized, finalize_session,
    load_resume_state, save_resume_state, session_continuation_for_spec, session_iterations_count,
    session_started_epoch, session_total_cost, session_total_iterations, IterationLogInput,
};
use crate::spec::{
    count_active, count_remaining, count_status, count_total, find_next_task, find_open_task,
    get_spec_name, get_task_name, list_spec_dirs, resolve_spec_dir, set_task_status, TaskStatus,
};
use crate::ui::Ui;
use crate::util::{
    command_exists, current_branch, format_cost, format_duration, head_sha, now_stamp,
    project_root, slugify,
};

pub fn cmd_init(args: &InitArgs, ui: &Ui) -> Result<i32> {
    ui.print_header(SPECLOOP_VERSION);
    println!();

    let config_path = Path::new(".speclooprc");
    if config_path.exists() && !args.force {
        bail!(".speclooprc already exists. Use --force to overwrite.");
    }

    let cwd = std::env::current_dir().context("failed to get current directory")?;
    let mut project_type = detect_project_type(&cwd);
    let mut verify_cmd = detect_verify_command(&project_type);
    let mut test_cmd = detect_test_command(&project_type);

    if let Some(v) = &args.verify_cmd {
        verify_cmd = v.clone();
    }
    if let Some(v) = &args.test_cmd {
        test_cmd = v.clone();
    }

    if !args.no_wizard && io::stdin().is_terminal() && io::stdout().is_terminal() {
        ui.phase("Initializing spec-loop");
        println!();

        ui.step_info(&format!(
            "Detected project type: {}",
            ui.bold(&project_type)
        ));
        project_type = prompt_with_default("Project type", &project_type)?;

        if verify_cmd.is_empty() {
            ui.step_warn("Could not detect verify command");
        } else {
            ui.step_info(&format!("Detected verify command: {}", ui.dim(&verify_cmd)));
        }
        verify_cmd = prompt_with_default("Verify command", &verify_cmd)?;

        if test_cmd.is_empty() {
            ui.step_warn("Could not detect test command");
        } else {
            ui.step_info(&format!("Detected test command: {}", ui.dim(&test_cmd)));
        }
        test_cmd = prompt_with_default("Test command", &test_cmd)?;
    }

    write_speclooprc(&project_type, &verify_cmd, &test_cmd)?;
    ui.step_ok("Created .speclooprc");

    fs::create_dir_all(".agents/specs").context("failed creating .agents/specs")?;
    fs::create_dir_all(".spec-loop/sessions").context("failed creating .spec-loop/sessions")?;
    ui.step_ok("Created .agents/ and .spec-loop/ directories");

    install_templates()?;
    ui.step_ok("Copied templates to .agents/templates/");

    if !Path::new(".agents/decisions.md").exists() {
        fs::write(
            ".agents/decisions.md",
            "# Decisions\n\nDesign decisions made during development. Append new entries at the bottom.\n",
        )
        .context("failed writing .agents/decisions.md")?;
        ui.step_ok("Created .agents/decisions.md");
    }

    if !Path::new("AGENTS.md").exists() {
        fs::write("AGENTS.md", default_agents_md()).context("failed writing AGENTS.md")?;
        ui.step_ok("Created starter AGENTS.md");
    }

    update_gitignore()?;
    ui.step_ok("Updated .gitignore");

    println!();
    ui.step_ok(&ui.bold("spec-loop initialized"));
    println!();
    ui.step_info("Next: edit AGENTS.md with your project's rules");
    ui.step_info(&format!(
        "Then:  run {} to create your first feature spec",
        ui.bold("/spec-loop-spec")
    ));

    Ok(EXIT_OK)
}

pub fn cmd_status(ui: &Ui) -> Result<i32> {
    let cfg = load_config(None)?;
    ui.print_header(SPECLOOP_VERSION);

    let specs_dir = Path::new(&cfg.specs_dir);
    if !specs_dir.is_dir() {
        println!();
        ui.step_info("No specs directory found. Run 'spec-loop init' first.");
        return Ok(EXIT_OK);
    }

    let all_specs = list_spec_dirs(specs_dir)?;
    if all_specs.is_empty() {
        println!();
        ui.step_info("No specs found. Use /spec-loop-spec to create a feature spec.");
        return Ok(EXIT_OK);
    }

    let mut found_active = false;
    for spec_dir in all_specs {
        let name = get_spec_name(&spec_dir);
        let total = count_total(&spec_dir);
        let done_count = count_status(&spec_dir, TaskStatus::Done);
        let pending_count = count_status(&spec_dir, TaskStatus::Pending);
        let in_review_count = count_status(&spec_dir, TaskStatus::InReview);
        let remaining = count_remaining(&spec_dir);
        let active_count = count_active(&spec_dir);

        if active_count > 0 {
            found_active = true;
            ui.box_header(&name, 52);
            ui.box_empty(52);
            ui.box_line(
                &format!(
                    "  {} {} {} remaining",
                    ui.progress_bar(done_count, total, 16, "done"),
                    ui.diamond(),
                    remaining
                ),
                52,
            );
            ui.box_line(
                &format!(
                    "  {} pending {} {} in-review",
                    pending_count,
                    ui.diamond(),
                    in_review_count
                ),
                52,
            );
            ui.box_line(&format!("  {}", current_branch()), 52);

            if let Some(next_task) = find_next_task(&spec_dir) {
                let task_name = get_task_name(&next_task);
                ui.box_line(&format!("  {} Next: {}", ui.arrow(), task_name), 52);
            }

            ui.box_empty(52);
            ui.box_footer(52);
        }
    }

    if let Some(lines) = recent_commits() {
        println!();
        println!("  {}", ui.dim("Recent commits"));
        for line in lines {
            println!("  {}", ui.dim(&format!("  {}", line)));
        }
    }

    if !found_active {
        println!();
        ui.step_info("No active specs (all tasks done or none created).");
        ui.step_info("Use /spec-loop-spec to create a new feature spec.");
    }

    println!();
    Ok(EXIT_OK)
}

pub fn cmd_run(args: &RunArgs, ui: &Ui) -> Result<i32> {
    let cfg = load_config(Some(args))?;
    preflight(&cfg)?;

    let session_dir = Path::new(&cfg.session_dir);
    let mut cb = CircuitBreaker::load(session_dir)?;

    let mut spec_dir = resolve_spec_dir(Path::new(&cfg.specs_dir), args.spec.as_deref())?;
    let mut spec_name = get_spec_name(&spec_dir);

    let mut loop_index: u32;
    let mut resume_phase = String::new();
    let mut resume_before_sha = String::new();
    let session_path: PathBuf;
    let mut mode = "new";

    if args.resume {
        if let Some(state) = load_resume_state(&cfg) {
            spec_dir = PathBuf::from(&state.spec_dir);
            spec_name = get_spec_name(&spec_dir);
            session_path = PathBuf::from(&state.session_path);
            loop_index = state.loop_index.max(1);
            resume_phase = state.phase;
            resume_before_sha = state.before_sha;
            mode = "resume";
            ui.step_info(&format!(
                "Resuming session for {} at iteration {} (phase: {})",
                spec_name, loop_index, resume_phase
            ));
        } else {
            let continuation = session_continuation_for_spec(session_dir, &spec_dir);
            if let Some(path) = continuation {
                session_path = path;
                loop_index = session_iterations_count(&session_path) + 1;
                mode = "continue";
                ui.step_info(&format!(
                    "Continuing session {} at iteration {}",
                    session_path
                        .file_name()
                        .map(|s| s.to_string_lossy().to_string())
                        .unwrap_or_else(|| "unknown".to_string()),
                    loop_index
                ));
            } else {
                session_path = new_session_path(&cfg, &spec_name);
                loop_index = 1;
            }
        }
    } else {
        let continuation = session_continuation_for_spec(session_dir, &spec_dir);
        if let Some(path) = continuation {
            session_path = path;
            loop_index = session_iterations_count(&session_path) + 1;
            mode = "continue";
            ui.step_info(&format!(
                "Continuing session {} at iteration {}",
                session_path
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_else(|| "unknown".to_string()),
                loop_index
            ));
        } else {
            session_path = new_session_path(&cfg, &spec_name);
            loop_index = 1;
        }
    }

    ensure_session_initialized(&session_path, &spec_dir, &spec_name, &cfg, SPECLOOP_VERSION)?;

    let total_tasks = count_total(&spec_dir);
    let done_tasks = count_status(&spec_dir, TaskStatus::Done);
    let pending_tasks = count_status(&spec_dir, TaskStatus::Pending);
    let in_review_tasks = count_status(&spec_dir, TaskStatus::InReview);
    let remaining_tasks = count_remaining(&spec_dir);

    ui.print_header(SPECLOOP_VERSION);
    ui.box_header("Spec", 52);
    ui.box_empty(52);
    ui.box_line(&format!("  {}", spec_name), 52);
    ui.box_line(
        &format!(
            "  {} {} {} remaining",
            ui.progress_bar(done_tasks, total_tasks, 16, "done"),
            ui.diamond(),
            remaining_tasks
        ),
        52,
    );
    ui.box_line(
        &format!(
            "  {} pending {} {} in-review",
            pending_tasks,
            ui.diamond(),
            in_review_tasks
        ),
        52,
    );
    ui.box_line(&format!("  {}", current_branch()), 52);
    if cfg.max_tasks_per_run > 0 {
        ui.box_line(
            &format!("  Task budget  {} this run", cfg.max_tasks_per_run),
            52,
        );
    }
    ui.box_empty(52);
    ui.box_footer(52);

    let mut total_cost = session_total_cost(&session_path);
    let total_iterations_base = session_total_iterations(&session_path);
    let started_epoch = session_started_epoch(&session_path);
    let mut iterations_completed = 0_u32;

    append_run_invocation_header(
        &session_path,
        mode,
        args.once,
        cfg.max_tasks_per_run,
        cfg.max_loops,
        args.skip_review,
    )?;

    while loop_index <= cfg.max_loops {
        if !cb.check(cfg.cb_cooldown_minutes, ui)? {
            finalize_session(
                &session_path,
                started_epoch,
                total_cost,
                "CIRCUIT_OPEN",
                total_iterations_base + iterations_completed,
            )?;
            clear_resume_state(&cfg);
            return Ok(EXIT_CIRCUIT_OPEN);
        }

        let remaining = count_remaining(&spec_dir);
        if remaining == 0 {
            loop_complete(
                &session_path,
                &spec_name,
                total_tasks,
                started_epoch,
                total_cost,
                total_iterations_base + iterations_completed,
                ui,
            )?;
            clear_resume_state(&cfg);
            return Ok(EXIT_OK);
        }

        if cfg.max_tasks_per_run > 0 && iterations_completed >= cfg.max_tasks_per_run {
            ui.step_ok(&format!(
                "Reached task budget ({}) for this run",
                cfg.max_tasks_per_run
            ));
            finalize_session(
                &session_path,
                started_epoch,
                total_cost,
                "TASK_LIMIT",
                total_iterations_base + iterations_completed,
            )?;
            clear_resume_state(&cfg);
            return Ok(EXIT_OK);
        }

        let next_task_file = find_next_task(&spec_dir).or_else(|| find_open_task(&spec_dir));
        let next_task_name = next_task_file
            .as_ref()
            .map(|p| get_task_name(p))
            .unwrap_or_default();

        if next_task_name.is_empty() {
            ui.separator(
                &format!("Iteration {} of {}", loop_index, cfg.max_loops),
                52,
            );
        } else {
            ui.separator(
                &format!(
                    "Iteration {} {} {}",
                    loop_index,
                    ui.diamond(),
                    next_task_name
                ),
                52,
            );
        }

        append_run_iteration_header(
            &session_path,
            loop_index,
            if next_task_name.is_empty() {
                None
            } else {
                Some(next_task_name.as_str())
            },
        )?;

        let iteration_start = Instant::now();

        let before_sha: String;
        let after_build_sha: String;
        let mut build_cost = 0.0_f64;
        let review_cost: f64;
        let mut fix_total_cost = 0.0_f64;
        let mut must_fix_count: u32;
        let mut should_fix_count: u32;
        let mut review_status: String;
        let mut review_findings: String;

        if resume_phase == "review" || resume_phase == "fix" {
            ui.step_info(&format!(
                "Skipping build (already completed, resuming at {})",
                resume_phase
            ));
            before_sha = resume_before_sha.clone();
            after_build_sha = head_sha();
            save_resume_state(
                &cfg,
                &spec_dir,
                loop_index,
                &session_path,
                &resume_phase,
                &before_sha,
            )?;
        } else {
            save_resume_state(&cfg, &spec_dir, loop_index, &session_path, "build", "")?;

            before_sha = head_sha();

            ui.phase("build");
            let prompt = build_prompt(&spec_dir, &cfg);
            let result = run_claude(&prompt, &cfg, args.dry_run, args.verbose)?;
            let build_status = parse_kv(&result.output_text, "BUILD_STATUS").unwrap_or_default();

            build_cost = result.cost_usd;
            total_cost += build_cost;

            append_run_phase(
                &session_path,
                "Build",
                if build_status.is_empty() {
                    "unknown"
                } else {
                    &build_status
                },
                result.cost_usd,
                result.duration_ms,
                &result.output_text,
                &prompt,
                &result.claude_session_id,
            )?;

            after_build_sha = head_sha();

            if has_tag(&result.output_text, "COMPLETE") {
                ui.step_ok("All tasks complete");
                iterations_completed += 1;
                append_iteration_log(
                    &session_path,
                    IterationLogInput {
                        index: loop_index,
                        task_name: &next_task_name,
                        outcome: "complete",
                        duration_seconds: iteration_start.elapsed().as_secs(),
                        cost_usd: build_cost,
                        must_fix_count: 0,
                        should_fix_count: 0,
                        commit_sha: &after_build_sha,
                    },
                )?;
                loop_complete(
                    &session_path,
                    &spec_name,
                    total_tasks,
                    started_epoch,
                    total_cost,
                    total_iterations_base + iterations_completed,
                    ui,
                )?;
                clear_resume_state(&cfg);
                return Ok(EXIT_OK);
            }

            if has_tag(&result.output_text, "BLOCKED") {
                ui.step_error("Build is BLOCKED");
                append_iteration_log(
                    &session_path,
                    IterationLogInput {
                        index: loop_index,
                        task_name: &next_task_name,
                        outcome: "blocked",
                        duration_seconds: iteration_start.elapsed().as_secs(),
                        cost_usd: build_cost,
                        must_fix_count: 0,
                        should_fix_count: 0,
                        commit_sha: &after_build_sha,
                    },
                )?;
                finalize_session(
                    &session_path,
                    started_epoch,
                    total_cost,
                    "BLOCKED",
                    total_iterations_base + iterations_completed,
                )?;
                clear_resume_state(&cfg);
                return Ok(EXIT_BLOCKED);
            }

            if build_status.is_empty() {
                bail!(
                    "Build output missing BUILD_STATUS — model did not comply with prompt format"
                );
            }

            match build_status.as_str() {
                "NO_PENDING_TASKS" => {
                    let still_remaining = count_remaining(&spec_dir);
                    if still_remaining > 0 {
                        ui.step_error(&format!(
                            "No pending tasks, but {} tasks remain (likely blocked/in-review)",
                            still_remaining
                        ));
                        append_iteration_log(
                            &session_path,
                            IterationLogInput {
                                index: loop_index,
                                task_name: &next_task_name,
                                outcome: "blocked-no-pending",
                                duration_seconds: iteration_start.elapsed().as_secs(),
                                cost_usd: build_cost,
                                must_fix_count: 0,
                                should_fix_count: 0,
                                commit_sha: &after_build_sha,
                            },
                        )?;
                        finalize_session(
                            &session_path,
                            started_epoch,
                            total_cost,
                            "BLOCKED",
                            total_iterations_base + iterations_completed,
                        )?;
                        clear_resume_state(&cfg);
                        return Ok(EXIT_BLOCKED);
                    }

                    ui.step_ok("No pending tasks");
                    iterations_completed += 1;
                    append_iteration_log(
                        &session_path,
                        IterationLogInput {
                            index: loop_index,
                            task_name: &next_task_name,
                            outcome: "no-pending",
                            duration_seconds: iteration_start.elapsed().as_secs(),
                            cost_usd: build_cost,
                            must_fix_count: 0,
                            should_fix_count: 0,
                            commit_sha: &after_build_sha,
                        },
                    )?;
                    loop_complete(
                        &session_path,
                        &spec_name,
                        total_tasks,
                        started_epoch,
                        total_cost,
                        total_iterations_base + iterations_completed,
                        ui,
                    )?;
                    clear_resume_state(&cfg);
                    return Ok(EXIT_OK);
                }
                "BLOCKED" => {
                    ui.step_error("Build reported BLOCKED");
                    append_iteration_log(
                        &session_path,
                        IterationLogInput {
                            index: loop_index,
                            task_name: &next_task_name,
                            outcome: "blocked",
                            duration_seconds: iteration_start.elapsed().as_secs(),
                            cost_usd: build_cost,
                            must_fix_count: 0,
                            should_fix_count: 0,
                            commit_sha: &after_build_sha,
                        },
                    )?;
                    finalize_session(
                        &session_path,
                        started_epoch,
                        total_cost,
                        "BLOCKED",
                        total_iterations_base + iterations_completed,
                    )?;
                    clear_resume_state(&cfg);
                    return Ok(EXIT_BLOCKED);
                }
                "COMPLETED_TASK" => {
                    if let Some(task_file) = &next_task_file {
                        let _ = set_task_status(task_file, TaskStatus::InReview);
                    }
                }
                other => bail!("Unexpected BUILD_STATUS: '{other}'"),
            }

            save_resume_state(
                &cfg,
                &spec_dir,
                loop_index,
                &session_path,
                "review",
                &before_sha,
            )?;
        }

        resume_phase.clear();
        resume_before_sha.clear();

        let current_head = head_sha();
        let mut made_progress = cb.last_commit().is_empty() || current_head != cb.last_commit();

        if args.skip_review {
            if let Some(task_file) = &next_task_file {
                let _ = set_task_status(task_file, TaskStatus::InReview);
            }

            let remaining = count_remaining(&spec_dir);
            ui.task_complete("Task ready for review", remaining);
            cb.record(made_progress, cfg.cb_no_progress_threshold, ui)?;

            append_iteration_log(
                &session_path,
                IterationLogInput {
                    index: loop_index,
                    task_name: &next_task_name,
                    outcome: "skip-review",
                    duration_seconds: iteration_start.elapsed().as_secs(),
                    cost_usd: build_cost,
                    must_fix_count: 0,
                    should_fix_count: 0,
                    commit_sha: &after_build_sha,
                },
            )?;

            iterations_completed += 1;
            loop_index += 1;
            continue;
        }

        ui.phase("review");
        let review_prompt_text = review_prompt(
            &spec_dir,
            &cfg,
            if before_sha.is_empty() {
                None
            } else {
                Some(before_sha.as_str())
            },
        );
        let review_result = run_claude(&review_prompt_text, &cfg, args.dry_run, args.verbose)?;
        review_cost = review_result.cost_usd;
        total_cost += review_cost;

        review_status = parse_kv(&review_result.output_text, "REVIEW_STATUS").unwrap_or_default();
        must_fix_count = parse_kv(&review_result.output_text, "MUST_FIX_COUNT")
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);
        should_fix_count = parse_kv(&review_result.output_text, "SHOULD_FIX_COUNT")
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);
        review_findings = review_result.output_text.clone();

        let review_phase_status = format!(
            "{}; must_fix={}; should_fix={}",
            if review_status.is_empty() {
                "unknown"
            } else {
                &review_status
            },
            must_fix_count,
            should_fix_count
        );
        append_run_phase(
            &session_path,
            "Review",
            &review_phase_status,
            review_result.cost_usd,
            review_result.duration_ms,
            &review_result.output_text,
            &review_prompt_text,
            &review_result.claude_session_id,
        )?;

        if has_tag(&review_result.output_text, "BLOCKED") {
            ui.step_error("Review is BLOCKED");
            finalize_session(
                &session_path,
                started_epoch,
                total_cost,
                "BLOCKED",
                total_iterations_base + iterations_completed,
            )?;
            clear_resume_state(&cfg);
            return Ok(EXIT_BLOCKED);
        }

        let needs_fix = review_status == "FAIL" || must_fix_count > 0 || should_fix_count > 0;
        if !needs_fix {
            if let Some(task_file) = &next_task_file {
                let _ = set_task_status(task_file, TaskStatus::Done);
            }

            ui.step_ok(&format!(
                "PASS  {}0 must-fix {} 0 should-fix",
                ui.dim(""),
                ui.diamond()
            ));

            let remaining = count_remaining(&spec_dir);
            ui.task_complete("Task done", remaining);
            cb.record(made_progress, cfg.cb_no_progress_threshold, ui)?;

            append_iteration_log(
                &session_path,
                IterationLogInput {
                    index: loop_index,
                    task_name: &next_task_name,
                    outcome: "pass",
                    duration_seconds: iteration_start.elapsed().as_secs(),
                    cost_usd: build_cost + review_cost,
                    must_fix_count,
                    should_fix_count,
                    commit_sha: &after_build_sha,
                },
            )?;

            iterations_completed += 1;
            loop_index += 1;
            continue;
        }

        ui.step_warn(&format!(
            "FAIL  {} must-fix {} {} should-fix",
            must_fix_count,
            ui.diamond(),
            should_fix_count
        ));

        save_resume_state(
            &cfg,
            &spec_dir,
            loop_index,
            &session_path,
            "fix",
            &before_sha,
        )?;

        let mut fix_try = 1_u32;
        let mut fix_passed = false;
        while fix_try <= cfg.max_review_fix_loops {
            ui.phase(&format!(
                "fix (attempt {}/{})",
                fix_try, cfg.max_review_fix_loops
            ));
            let fix_prompt_text = fix_prompt(&spec_dir, &cfg, &review_findings);
            let fix_result = run_claude(&fix_prompt_text, &cfg, args.dry_run, args.verbose)?;
            total_cost += fix_result.cost_usd;
            fix_total_cost += fix_result.cost_usd;

            append_run_phase(
                &session_path,
                &format!("Fix (attempt {})", fix_try),
                "applied",
                fix_result.cost_usd,
                fix_result.duration_ms,
                &fix_result.output_text,
                &fix_prompt_text,
                &fix_result.claude_session_id,
            )?;

            if has_tag(&fix_result.output_text, "BLOCKED") {
                ui.step_error("Fix build is BLOCKED");
                finalize_session(
                    &session_path,
                    started_epoch,
                    total_cost,
                    "BLOCKED",
                    total_iterations_base + iterations_completed,
                )?;
                clear_resume_state(&cfg);
                return Ok(EXIT_BLOCKED);
            }

            ui.phase("review (recheck)");
            let recheck_prompt_text = review_prompt(
                &spec_dir,
                &cfg,
                if before_sha.is_empty() {
                    None
                } else {
                    Some(before_sha.as_str())
                },
            );
            let recheck_result =
                run_claude(&recheck_prompt_text, &cfg, args.dry_run, args.verbose)?;
            total_cost += recheck_result.cost_usd;
            fix_total_cost += recheck_result.cost_usd;

            review_status =
                parse_kv(&recheck_result.output_text, "REVIEW_STATUS").unwrap_or_default();
            must_fix_count = parse_kv(&recheck_result.output_text, "MUST_FIX_COUNT")
                .and_then(|s| s.parse::<u32>().ok())
                .unwrap_or(0);
            should_fix_count = parse_kv(&recheck_result.output_text, "SHOULD_FIX_COUNT")
                .and_then(|s| s.parse::<u32>().ok())
                .unwrap_or(0);
            review_findings = recheck_result.output_text.clone();

            let recheck_phase_status = format!(
                "{}; must_fix={}; should_fix={}",
                if review_status.is_empty() {
                    "unknown"
                } else {
                    &review_status
                },
                must_fix_count,
                should_fix_count
            );
            append_run_phase(
                &session_path,
                &format!("Review (recheck {})", fix_try),
                &recheck_phase_status,
                recheck_result.cost_usd,
                recheck_result.duration_ms,
                &recheck_result.output_text,
                &recheck_prompt_text,
                &recheck_result.claude_session_id,
            )?;

            if has_tag(&recheck_result.output_text, "BLOCKED") {
                ui.step_error("Review recheck is BLOCKED");
                finalize_session(
                    &session_path,
                    started_epoch,
                    total_cost,
                    "BLOCKED",
                    total_iterations_base + iterations_completed,
                )?;
                clear_resume_state(&cfg);
                return Ok(EXIT_BLOCKED);
            }

            if review_status == "PASS" && must_fix_count == 0 && should_fix_count == 0 {
                ui.step_ok(&format!("PASS after fix attempt {}", fix_try));
                fix_passed = true;
                break;
            }

            ui.step_warn(&format!(
                "Still failing: {} must-fix {} {} should-fix",
                must_fix_count,
                ui.diamond(),
                should_fix_count
            ));
            fix_try += 1;
        }

        if !fix_passed {
            bail!(
                "Review still failing after {} fix attempts",
                cfg.max_review_fix_loops
            );
        }

        if let Some(task_file) = &next_task_file {
            let _ = set_task_status(task_file, TaskStatus::Done);
        }

        let current_head = head_sha();
        made_progress = cb.last_commit().is_empty() || current_head != cb.last_commit();

        let remaining = count_remaining(&spec_dir);
        ui.task_complete("Task done", remaining);
        cb.record(made_progress, cfg.cb_no_progress_threshold, ui)?;

        let after_fix_sha = head_sha();
        append_iteration_log(
            &session_path,
            IterationLogInput {
                index: loop_index,
                task_name: &next_task_name,
                outcome: "pass-after-fix",
                duration_seconds: iteration_start.elapsed().as_secs(),
                cost_usd: build_cost + review_cost + fix_total_cost,
                must_fix_count,
                should_fix_count,
                commit_sha: &after_fix_sha,
            },
        )?;

        iterations_completed += 1;
        loop_index += 1;
    }

    if args.once {
        let remaining = count_remaining(&spec_dir);
        ui.step_ok(&format!(
            "Single cycle completed (--once). {} tasks may remain.",
            remaining
        ));
        finalize_session(
            &session_path,
            started_epoch,
            total_cost,
            "ONCE",
            total_iterations_base + iterations_completed,
        )?;
        clear_resume_state(&cfg);
        return Ok(EXIT_OK);
    }

    finalize_session(
        &session_path,
        started_epoch,
        total_cost,
        "MAX_ITERATIONS",
        total_iterations_base + iterations_completed,
    )?;
    clear_resume_state(&cfg);
    ui.step_error(&format!(
        "Reached max loops ({}) with pending tasks still present",
        cfg.max_loops
    ));
    Ok(EXIT_MAX_ITERATIONS)
}

fn preflight(cfg: &Config) -> Result<()> {
    if !command_exists(&cfg.claude_bin) {
        bail!("Required command not found: {}", cfg.claude_bin);
    }

    let _ = project_root().context("Not inside a git repository. Run 'git init' first.")?;

    if !Path::new(&cfg.speclooprc).exists() {
        bail!("No .speclooprc found. Run 'spec-loop init' first.");
    }

    if cfg.max_loops == 0 {
        bail!("MAX_LOOPS must be a positive integer (got: 0)");
    }
    if cfg.max_review_fix_loops == 0 {
        bail!("MAX_REVIEW_FIX_LOOPS must be a positive integer (got: 0)");
    }

    fs::create_dir_all(&cfg.session_dir)
        .with_context(|| format!("failed to create {}", cfg.session_dir))?;

    if !Path::new(&cfg.specs_dir).is_dir() {
        bail!(
            "Specs directory not found: {}\n  Run 'spec-loop init' or create it manually.",
            cfg.specs_dir
        );
    }

    Ok(())
}

fn loop_complete(
    session_path: &Path,
    spec_name: &str,
    total_tasks: usize,
    started_epoch: i64,
    total_cost: f64,
    iterations: u32,
    ui: &Ui,
) -> Result<()> {
    let end_epoch = chrono::Utc::now().timestamp();
    let duration_s = (end_epoch - started_epoch).max(0) as u64;

    ui.box_header("Complete", 52);
    ui.box_empty(52);
    ui.box_line("  All tasks done", 52);
    ui.box_empty(52);
    ui.box_line(&format!("  Spec        {}", spec_name), 52);
    ui.box_line(&format!("  Tasks       {} completed", total_tasks), 52);
    ui.box_line(&format!("  Iterations  {}", iterations), 52);
    ui.box_line(
        &format!("  Duration    {}", format_duration(duration_s)),
        52,
    );
    ui.box_line(&format!("  Cost        {}", format_cost(total_cost)), 52);
    ui.box_empty(52);
    ui.box_footer(52);

    finalize_session(
        session_path,
        started_epoch,
        total_cost,
        "COMPLETE",
        iterations,
    )
}

fn new_session_path(cfg: &Config, spec_name: &str) -> PathBuf {
    let session_id = format!("{}_{}", now_stamp(), slugify(spec_name));
    Path::new(&cfg.session_dir).join(session_id)
}

fn prompt_with_default(label: &str, default: &str) -> Result<String> {
    print!("  {} [{}]: ", label, default);
    io::stdout().flush().ok();

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .context("failed to read interactive input")?;
    let value = input.trim();
    if value.is_empty() {
        Ok(default.to_string())
    } else {
        Ok(value.to_string())
    }
}

fn write_speclooprc(project_type: &str, verify_cmd: &str, test_cmd: &str) -> Result<()> {
    let content = format!(
        "# spec-loop configuration\n# Generated by spec-loop init\n\n# Project\nPROJECT_TYPE=\"{}\"\nVERIFY_COMMAND=\"{}\"\nTEST_COMMAND=\"{}\"\n\n# Claude Code\n# CLAUDE_MODEL=\"\"\n\n# Loop limits\n# MAX_LOOPS={}\n# MAX_REVIEW_FIX_LOOPS={}\n# MAX_TASKS_PER_RUN=0\n\n# Safety\n# CB_NO_PROGRESS_THRESHOLD=3\n# CB_COOLDOWN_MINUTES=30\n\n# Paths\n# SPECS_DIR=\".agents/specs\"\n# SESSION_DIR=\".spec-loop/sessions\"\n",
        project_type,
        verify_cmd,
        test_cmd,
        DEFAULT_MAX_LOOPS,
        DEFAULT_MAX_REVIEW_FIX_LOOPS,
    );
    fs::write(".speclooprc", content).context("failed writing .speclooprc")
}

fn install_templates() -> Result<()> {
    fs::create_dir_all(".agents/templates").context("failed creating .agents/templates")?;

    let templates = [
        (
            ".agents/templates/spec.md",
            include_str!("../.agents/templates/spec.md"),
        ),
        (
            ".agents/templates/task.md",
            include_str!("../.agents/templates/task.md"),
        ),
        (
            ".agents/templates/progress.md",
            include_str!("../.agents/templates/progress.md"),
        ),
    ];

    for (path, content) in templates {
        if !Path::new(path).exists() {
            fs::write(path, content).with_context(|| format!("failed writing {path}"))?;
        }
    }

    Ok(())
}

fn default_agents_md() -> &'static str {
    "# AGENTS.md\n\nProject conventions and architecture rules for AI agents.\n\n## Project Overview\n\n<!-- Describe what this project does, its architecture, and key technologies. -->\n\n## Conventions\n\n<!-- Add your project's coding conventions:\n- Naming: files, functions, variables\n- Structure: where things live, how modules are organized\n- Patterns: common patterns to follow\n- Anti-patterns: things to avoid\n-->\n\n## Review Checklist\n\n<!-- Add project-specific review criteria:\n- Architecture rules\n- Type safety requirements\n- Test coverage expectations\n- Security considerations\n-->\n"
}

fn update_gitignore() -> Result<()> {
    let marker = "# spec-loop";
    let entry = ".spec-loop/";
    let path = Path::new(".gitignore");

    let existing = if path.exists() {
        fs::read_to_string(path).unwrap_or_default()
    } else {
        String::new()
    };

    if existing.contains(marker) {
        return Ok(());
    }

    let mut out = existing;
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    out.push('\n');
    out.push_str(marker);
    out.push('\n');
    out.push_str(entry);
    out.push('\n');

    fs::write(path, out).context("failed writing .gitignore")
}

fn recent_commits() -> Option<Vec<String>> {
    let out = Command::new("git")
        .args(["log", "--oneline", "-5"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<String> = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    if lines.is_empty() {
        None
    } else {
        Some(lines)
    }
}
