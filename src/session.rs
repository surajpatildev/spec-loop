use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::config::Config;
use crate::util::{format_cost, format_duration, now_human, now_iso};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionIteration {
    pub index: u32,
    pub task: String,
    pub outcome: String,
    pub duration_seconds: u64,
    pub cost_usd: f64,
    pub must_fix_count: u32,
    pub should_fix_count: u32,
    pub commit: String,
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInvocation {
    pub started_at: String,
    pub mode: String,
    pub once: bool,
    pub max_tasks: u32,
    pub max_loops: u32,
    pub skip_review: bool,
    #[serde(default)]
    pub claude_session_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionJson {
    pub session_id: String,
    pub version: String,
    pub spec: String,
    pub spec_name: String,
    pub started_at: String,
    pub max_loops: u32,
    pub max_review_fix_loops: u32,
    pub max_tasks_per_run: u32,
    #[serde(default)]
    pub claude_sessions: Vec<String>,
    #[serde(default)]
    pub invocations: Vec<SessionInvocation>,
    #[serde(default)]
    pub iterations: Vec<SessionIteration>,
    #[serde(default)]
    pub ended_at: Option<String>,
    #[serde(default)]
    pub duration_seconds: Option<u64>,
    #[serde(default)]
    pub total_cost_usd: Option<f64>,
    #[serde(default)]
    pub exit_reason: Option<String>,
    #[serde(default)]
    pub total_iterations: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResumeState {
    pub spec_dir: String,
    pub loop_index: u32,
    pub session_path: String,
    pub phase: String,
    pub before_sha: String,
    pub saved_at: String,
}

pub fn session_state_path(cfg: &Config) -> PathBuf {
    Path::new(&cfg.session_dir).join(".session_state.json")
}

pub fn save_resume_state(
    cfg: &Config,
    spec_dir: &Path,
    loop_index: u32,
    session_path: &Path,
    phase: &str,
    before_sha: &str,
) -> Result<()> {
    fs::create_dir_all(&cfg.session_dir)
        .with_context(|| format!("failed to create {}", cfg.session_dir))?;

    let state = ResumeState {
        spec_dir: spec_dir.display().to_string(),
        loop_index,
        session_path: session_path.display().to_string(),
        phase: phase.to_string(),
        before_sha: before_sha.to_string(),
        saved_at: now_iso(),
    };

    let path = session_state_path(cfg);
    let text = serde_json::to_string_pretty(&state)?;
    fs::write(&path, text).with_context(|| format!("failed to write {}", path.display()))
}

pub fn load_resume_state(cfg: &Config) -> Option<ResumeState> {
    let path = session_state_path(cfg);
    let text = fs::read_to_string(path).ok()?;
    let state: ResumeState = serde_json::from_str(&text).ok()?;
    if state.spec_dir.is_empty() || !Path::new(&state.spec_dir).exists() {
        return None;
    }
    Some(state)
}

pub fn clear_resume_state(cfg: &Config) {
    let _ = fs::remove_file(session_state_path(cfg));
}

pub fn session_json_path(session_path: &Path) -> PathBuf {
    session_path.join("session.json")
}

pub fn session_runlog_path(session_path: &Path) -> PathBuf {
    session_path.join("run.md")
}

pub fn session_log_path(session_path: &Path) -> PathBuf {
    session_path.join("session.md")
}

pub fn write_session_json(path: &Path, data: &SessionJson) -> Result<()> {
    let text = serde_json::to_string_pretty(data)?;
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

pub fn read_session_json(path: &Path) -> Result<SessionJson> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("failed to parse {}", path.display()))
}

pub fn ensure_session_initialized(
    session_path: &Path,
    spec_dir: &Path,
    spec_name: &str,
    cfg: &Config,
    version: &str,
) -> Result<()> {
    fs::create_dir_all(session_path)
        .with_context(|| format!("failed to create {}", session_path.display()))?;

    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        let data = SessionJson {
            session_id: session_path
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "unknown-session".to_string()),
            version: version.to_string(),
            spec: spec_dir.display().to_string(),
            spec_name: spec_name.to_string(),
            started_at: now_iso(),
            max_loops: cfg.max_loops,
            max_review_fix_loops: cfg.max_review_fix_loops,
            max_tasks_per_run: cfg.max_tasks_per_run,
            claude_sessions: vec![],
            invocations: vec![],
            iterations: vec![],
            ended_at: None,
            duration_seconds: None,
            total_cost_usd: None,
            exit_reason: None,
            total_iterations: None,
        };
        write_session_json(&json_path, &data)?;
    }

    let run_path = session_runlog_path(session_path);
    if !run_path.exists() {
        let run_md = format!(
            "# Run Log\n\n- Spec: {}\n- Spec path: {}\n- Started: {}\n\n---\n",
            spec_name,
            spec_dir.display(),
            now_human(),
        );
        fs::write(&run_path, run_md)
            .with_context(|| format!("failed to write {}", run_path.display()))?;
    }

    Ok(())
}

pub fn append_run_invocation_header(
    session_path: &Path,
    mode: &str,
    once: bool,
    max_tasks: u32,
    max_loops: u32,
    skip_review: bool,
) -> Result<()> {
    let run_path = session_runlog_path(session_path);
    let session_id = session_path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown-session".to_string());

    let started_at = now_iso();
    let content = format!(
        "\n## Invocation — {}\n- Spec-loop Session ID: {}\n- Mode: {}\n- Flags: once={}, max_tasks={}, max_loops={}, skip_review={}\n- Claude Sessions: recorded per phase below and in session.json invocations[].claude_session_ids\n\n",
        now_human(),
        session_id,
        mode,
        once,
        max_tasks,
        max_loops,
        skip_review,
    );
    append_text(&run_path, &content)?;

    let json_path = session_json_path(session_path);
    if json_path.exists() {
        let mut data = read_session_json(&json_path)?;
        data.invocations.push(SessionInvocation {
            started_at,
            mode: mode.to_string(),
            once,
            max_tasks,
            max_loops,
            skip_review,
            claude_session_ids: vec![],
        });
        write_session_json(&json_path, &data)?;
    }

    Ok(())
}

pub fn append_run_iteration_header(
    session_path: &Path,
    index: u32,
    task_name: Option<&str>,
) -> Result<()> {
    let run_path = session_runlog_path(session_path);
    let mut content = format!("\n## Iteration {} — {}\n", index, now_human());
    if let Some(task) = task_name.filter(|t| !t.is_empty()) {
        content.push_str(&format!("- Task: {}\n", task));
    }
    content.push('\n');
    append_text(&run_path, &content)
}

pub fn register_claude_session(session_path: &Path, claude_session_id: &str) -> Result<()> {
    let id = claude_session_id.trim();
    if id.is_empty() {
        return Ok(());
    }

    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return Ok(());
    }

    let mut data = read_session_json(&json_path)?;

    if !data.claude_sessions.iter().any(|v| v == id) {
        data.claude_sessions.push(id.to_string());
    }

    if let Some(inv) = data.invocations.last_mut() {
        if !inv.claude_session_ids.iter().any(|v| v == id) {
            inv.claude_session_ids.push(id.to_string());
        }
    }

    write_session_json(&json_path, &data)
}

pub fn append_run_phase(
    session_path: &Path,
    phase_name: &str,
    status: &str,
    cost_usd: f64,
    duration_ms: u64,
    output: &str,
    prompt: &str,
    claude_session_id: &str,
) -> Result<()> {
    let run_path = session_runlog_path(session_path);
    let duration_s = duration_ms / 1000;

    let mut content = String::new();
    content.push_str(&format!("### {}\n", phase_name));
    content.push_str(&format!("- Status: {}\n", status));
    content.push_str(&format!("- Duration: {}\n", format_duration(duration_s)));
    content.push_str(&format!("- Cost: {}\n", format_cost(cost_usd)));
    if !claude_session_id.trim().is_empty() {
        content.push_str(&format!("- Claude Session: {}\n", claude_session_id));
    }
    content.push('\n');

    if !prompt.trim().is_empty() {
        content.push_str("#### Prompt\n\n");
        content.push_str(prompt);
        if !prompt.ends_with('\n') {
            content.push('\n');
        }
        content.push('\n');
    }

    content.push_str("#### Output\n\n");
    content.push_str(output);
    if !output.ends_with('\n') {
        content.push('\n');
    }
    content.push('\n');

    append_text(&run_path, &content)
}

pub struct IterationLogInput<'a> {
    pub index: u32,
    pub task_name: &'a str,
    pub outcome: &'a str,
    pub duration_seconds: u64,
    pub cost_usd: f64,
    pub must_fix_count: u32,
    pub should_fix_count: u32,
    pub commit_sha: &'a str,
}

pub fn append_iteration_log(session_path: &Path, input: IterationLogInput<'_>) -> Result<()> {
    let md_path = session_log_path(session_path);
    if !md_path.exists() {
        fs::write(&md_path, "# Session Log\n\n")
            .with_context(|| format!("failed to write {}", md_path.display()))?;
    }

    let short_sha = input.commit_sha.chars().take(7).collect::<String>();
    let mut md = String::new();
    md.push_str(&format!("## Iteration {} — {}\n", input.index, now_human()));
    if !input.task_name.trim().is_empty() {
        md.push_str(&format!("- Task: {}\n", input.task_name));
    }
    md.push_str(&format!("- Outcome: {}\n", input.outcome));
    md.push_str(&format!(
        "- Duration: {}\n",
        format_duration(input.duration_seconds)
    ));
    md.push_str(&format!("- Cost: {}\n", format_cost(input.cost_usd)));
    md.push_str(&format!("- Must-fix: {}\n", input.must_fix_count));
    md.push_str(&format!("- Should-fix: {}\n", input.should_fix_count));
    if !short_sha.is_empty() {
        md.push_str(&format!("- Commit: {}\n", short_sha));
    }
    md.push('\n');
    append_text(&md_path, &md)?;

    let json_path = session_json_path(session_path);
    if json_path.exists() {
        let mut data = read_session_json(&json_path)?;
        data.iterations.push(SessionIteration {
            index: input.index,
            task: input.task_name.to_string(),
            outcome: input.outcome.to_string(),
            duration_seconds: input.duration_seconds,
            cost_usd: input.cost_usd,
            must_fix_count: input.must_fix_count,
            should_fix_count: input.should_fix_count,
            commit: input.commit_sha.to_string(),
            timestamp: now_iso(),
        });
        write_session_json(&json_path, &data)?;
    }

    Ok(())
}

pub fn finalize_session(
    session_path: &Path,
    started_epoch: i64,
    total_cost_usd: f64,
    exit_reason: &str,
    total_iterations: u32,
) -> Result<()> {
    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return Ok(());
    }

    let mut data = read_session_json(&json_path)?;
    let now_epoch = Utc::now().timestamp();
    let duration = (now_epoch - started_epoch).max(0) as u64;
    data.ended_at = Some(now_iso());
    data.duration_seconds = Some(duration);
    data.total_cost_usd = Some(total_cost_usd);
    data.exit_reason = Some(exit_reason.to_string());
    data.total_iterations = Some(total_iterations);
    write_session_json(&json_path, &data)
}

pub fn session_iterations_count(session_path: &Path) -> u32 {
    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return 0;
    }
    read_session_json(&json_path)
        .map(|s| s.iterations.len() as u32)
        .unwrap_or(0)
}

pub fn session_total_iterations(session_path: &Path) -> u32 {
    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return 0;
    }
    read_session_json(&json_path)
        .map(|s| s.total_iterations.unwrap_or(s.iterations.len() as u32))
        .unwrap_or(0)
}

pub fn session_total_cost(session_path: &Path) -> f64 {
    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return 0.0;
    }
    read_session_json(&json_path)
        .map(|s| s.total_cost_usd.unwrap_or(0.0))
        .unwrap_or(0.0)
}

pub fn session_started_epoch(session_path: &Path) -> i64 {
    let json_path = session_json_path(session_path);
    if !json_path.exists() {
        return Utc::now().timestamp();
    }
    let started = read_session_json(&json_path)
        .ok()
        .map(|s| s.started_at)
        .unwrap_or_else(now_iso);
    parse_iso_epoch(&started).unwrap_or_else(|| Utc::now().timestamp())
}

pub fn session_latest_for_spec(session_dir: &Path, spec_dir: &Path) -> Option<PathBuf> {
    let spec = spec_dir.display().to_string();
    for dir in list_session_dirs_desc(session_dir) {
        let json_path = session_json_path(&dir);
        if !json_path.exists() {
            continue;
        }
        let Ok(data) = read_session_json(&json_path) else {
            continue;
        };
        if data.spec == spec {
            return Some(dir);
        }
    }
    None
}

pub fn session_continuation_for_spec(session_dir: &Path, spec_dir: &Path) -> Option<PathBuf> {
    let latest = session_latest_for_spec(session_dir, spec_dir)?;
    let data = read_session_json(&session_json_path(&latest)).ok()?;
    match data.exit_reason.as_deref() {
        Some("ONCE") | Some("TASK_LIMIT") => Some(latest),
        _ => None,
    }
}

fn list_session_dirs_desc(session_dir: &Path) -> Vec<PathBuf> {
    if !session_dir.is_dir() {
        return vec![];
    }
    let mut dirs = vec![];
    if let Ok(rd) = fs::read_dir(session_dir) {
        for entry in rd.flatten() {
            let path = entry.path();
            if path.is_dir() {
                dirs.push(path);
            }
        }
    }
    dirs.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
    dirs
}

fn append_text(path: &Path, text: &str) -> Result<()> {
    use std::io::Write;

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("failed to open {}", path.display()))?;
    file.write_all(text.as_bytes())
        .with_context(|| format!("failed to append {}", path.display()))
}

fn parse_iso_epoch(iso: &str) -> Option<i64> {
    DateTime::parse_from_rfc3339(iso)
        .ok()
        .map(|dt| dt.with_timezone(&Utc).timestamp())
}
