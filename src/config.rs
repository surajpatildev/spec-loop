use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};

use crate::cli::RunArgs;

pub const DEFAULT_MAX_LOOPS: u32 = 25;
pub const DEFAULT_MAX_REVIEW_FIX_LOOPS: u32 = 3;
pub const DEFAULT_MAX_TASKS_PER_RUN: u32 = 0;
pub const DEFAULT_CLAUDE_BIN: &str = "claude";
pub const DEFAULT_SPECS_DIR: &str = ".agents/specs";
pub const DEFAULT_SESSION_DIR: &str = ".spec-loop/sessions";
pub const DEFAULT_CB_NO_PROGRESS_THRESHOLD: u32 = 3;
pub const DEFAULT_CB_COOLDOWN_MINUTES: u32 = 30;

#[derive(Debug, Clone)]
pub struct Config {
    pub speclooprc: String,
    pub project_type: String,
    pub verify_command: String,
    pub test_command: String,
    pub claude_bin: String,
    pub claude_model: String,
    pub claude_extra_args: String,
    pub specs_dir: String,
    pub session_dir: String,
    pub max_loops: u32,
    pub max_review_fix_loops: u32,
    pub max_tasks_per_run: u32,
    pub cb_no_progress_threshold: u32,
    pub cb_cooldown_minutes: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            speclooprc: ".speclooprc".to_string(),
            project_type: String::new(),
            verify_command: String::new(),
            test_command: String::new(),
            claude_bin: env::var("CLAUDE_BIN").unwrap_or_else(|_| DEFAULT_CLAUDE_BIN.to_string()),
            claude_model: String::new(),
            claude_extra_args: env::var("CLAUDE_EXTRA_ARGS").unwrap_or_default(),
            specs_dir: DEFAULT_SPECS_DIR.to_string(),
            session_dir: DEFAULT_SESSION_DIR.to_string(),
            max_loops: DEFAULT_MAX_LOOPS,
            max_review_fix_loops: DEFAULT_MAX_REVIEW_FIX_LOOPS,
            max_tasks_per_run: DEFAULT_MAX_TASKS_PER_RUN,
            cb_no_progress_threshold: DEFAULT_CB_NO_PROGRESS_THRESHOLD,
            cb_cooldown_minutes: DEFAULT_CB_COOLDOWN_MINUTES,
        }
    }
}

pub fn parse_speclooprc(path: &Path) -> Result<HashMap<String, String>> {
    let mut out = HashMap::new();
    if !path.exists() {
        return Ok(out);
    }

    let content =
        fs::read_to_string(path).with_context(|| format!("failed to read {}", path.display()))?;
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let key = k.trim().to_string();
            let mut val = v.trim().to_string();
            if (val.starts_with('"') && val.ends_with('"'))
                || (val.starts_with('\'') && val.ends_with('\''))
            {
                val = val[1..val.len().saturating_sub(1)].to_string();
            }
            out.insert(key, val);
        }
    }

    Ok(out)
}

pub fn load_config(run_args: Option<&RunArgs>) -> Result<Config> {
    let mut cfg = Config::default();
    let rc = parse_speclooprc(Path::new(&cfg.speclooprc))?;

    apply_map(&mut cfg, &rc);

    // env overrides
    if let Ok(v) = env::var("SPECLOOP_MAX_LOOPS") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_loops = n;
        }
    }
    if let Ok(v) = env::var("SPECLOOP_MAX_REVIEW_FIX_LOOPS") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_review_fix_loops = n;
        }
    }
    if let Ok(v) = env::var("SPECLOOP_MAX_TASKS_PER_RUN") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_tasks_per_run = n;
        }
    }
    if let Ok(v) = env::var("SPECLOOP_SPECS_DIR") {
        cfg.specs_dir = v;
    }
    if let Ok(v) = env::var("SPECLOOP_SESSION_DIR") {
        cfg.session_dir = v;
    }

    // CLI overrides
    if let Some(args) = run_args {
        if let Some(v) = args.max_loops {
            cfg.max_loops = v;
        }
        if let Some(v) = args.max_review_fix_loops {
            cfg.max_review_fix_loops = v;
        }
        if let Some(v) = args.max_tasks {
            cfg.max_tasks_per_run = v;
        }
        if args.once {
            cfg.max_loops = 1;
            cfg.max_tasks_per_run = 1;
        }
    }

    Ok(cfg)
}

fn apply_map(cfg: &mut Config, map: &HashMap<String, String>) {
    if let Some(v) = map.get("PROJECT_TYPE") {
        cfg.project_type = v.clone();
    }
    if let Some(v) = map.get("VERIFY_COMMAND") {
        cfg.verify_command = v.clone();
    }
    if let Some(v) = map.get("TEST_COMMAND") {
        cfg.test_command = v.clone();
    }
    if let Some(v) = map.get("CLAUDE_BIN") {
        cfg.claude_bin = v.clone();
    }
    if let Some(v) = map.get("CLAUDE_MODEL") {
        cfg.claude_model = v.clone();
    }
    if let Some(v) = map.get("CLAUDE_EXTRA_ARGS") {
        cfg.claude_extra_args = v.clone();
    }
    if let Some(v) = map.get("SPECS_DIR") {
        cfg.specs_dir = v.clone();
    }
    if let Some(v) = map.get("SESSION_DIR") {
        cfg.session_dir = v.clone();
    }
    if let Some(v) = map.get("MAX_LOOPS") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_loops = n;
        }
    }
    if let Some(v) = map.get("MAX_REVIEW_FIX_LOOPS") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_review_fix_loops = n;
        }
    }
    if let Some(v) = map.get("MAX_TASKS_PER_RUN") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.max_tasks_per_run = n;
        }
    }
    if let Some(v) = map.get("CB_NO_PROGRESS_THRESHOLD") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.cb_no_progress_threshold = n;
        }
    }
    if let Some(v) = map.get("CB_COOLDOWN_MINUTES") {
        if let Ok(n) = v.parse::<u32>() {
            cfg.cb_cooldown_minutes = n;
        }
    }
}

pub fn detect_project_type(cwd: &Path) -> String {
    let has = |name: &str| cwd.join(name).exists();
    if has("tsconfig.json") {
        "typescript".to_string()
    } else if has("package.json") {
        "javascript".to_string()
    } else if has("pyproject.toml") || has("setup.py") || has("setup.cfg") {
        "python".to_string()
    } else if has("Cargo.toml") {
        "rust".to_string()
    } else if has("go.mod") {
        "go".to_string()
    } else if has("Gemfile") {
        "ruby".to_string()
    } else if has("build.gradle") || has("build.gradle.kts") {
        "java".to_string()
    } else if has("Package.swift") {
        "swift".to_string()
    } else {
        "generic".to_string()
    }
}

pub fn detect_verify_command(project_type: &str) -> String {
    match project_type {
        "typescript" => "npm run lint && npm run typecheck".to_string(),
        "javascript" => "npm run lint".to_string(),
        "python" => "python -m py_compile".to_string(),
        "rust" => "cargo clippy && cargo check".to_string(),
        "go" => "go vet ./...".to_string(),
        "ruby" => "bundle exec rubocop".to_string(),
        "java" => "./gradlew check".to_string(),
        "swift" => "swift build".to_string(),
        _ => String::new(),
    }
}

pub fn detect_test_command(project_type: &str) -> String {
    match project_type {
        "typescript" | "javascript" => "npm test".to_string(),
        "python" => "python -m pytest".to_string(),
        "rust" => "cargo test".to_string(),
        "go" => "go test ./...".to_string(),
        "ruby" => "bundle exec rspec".to_string(),
        "java" => "./gradlew test".to_string(),
        "swift" => "swift test".to_string(),
        _ => String::new(),
    }
}
