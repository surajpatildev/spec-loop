use chrono::Utc;
use regex::Regex;
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn now_iso() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

pub fn now_human() -> String {
    chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

pub fn now_stamp() -> String {
    chrono::Local::now().format("%Y%m%d_%H%M%S").to_string()
}

pub fn format_duration(secs: u64) -> String {
    if secs < 60 {
        format!("{}s", secs)
    } else if secs < 3600 {
        format!("{}m {}s", secs / 60, secs % 60)
    } else {
        format!("{}h {}m", secs / 3600, (secs % 3600) / 60)
    }
}

pub fn format_cost(v: f64) -> String {
    format!("${:.2}", v)
}

pub fn slugify(s: &str) -> String {
    let lower = s.to_lowercase();
    let re = Regex::new(r"[^a-z0-9._-]+").expect("valid regex");
    let out = re.replace_all(&lower, "-").trim_matches('-').to_string();
    if out.is_empty() {
        "session".to_string()
    } else {
        out
    }
}

pub fn current_branch() -> String {
    match Command::new("git")
        .args(["branch", "--show-current"])
        .output()
    {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        _ => "unknown".to_string(),
    }
}

pub fn head_sha() -> String {
    match Command::new("git")
        .args(["rev-parse", "--verify", "HEAD"])
        .output()
    {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        _ => String::new(),
    }
}

pub fn command_exists(cmd: &str) -> bool {
    if cmd.contains('/') {
        Path::new(cmd).exists()
    } else {
        env::var("PATH")
            .ok()
            .map(|path| {
                path.split(':')
                    .map(PathBuf::from)
                    .map(|p| p.join(cmd))
                    .any(|p| p.exists())
            })
            .unwrap_or(false)
    }
}
