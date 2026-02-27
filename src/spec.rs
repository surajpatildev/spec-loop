use anyhow::{anyhow, Context, Result};
use regex::Regex;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskStatus {
    Pending,
    InProgress,
    InReview,
    Done,
    Blocked,
    Unknown,
}

impl TaskStatus {
    pub fn from_str(s: &str) -> Self {
        match s.trim().to_lowercase().as_str() {
            "pending" => Self::Pending,
            "in-progress" => Self::InProgress,
            "in-review" => Self::InReview,
            "done" => Self::Done,
            "blocked" => Self::Blocked,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::InProgress => "in-progress",
            Self::InReview => "in-review",
            Self::Done => "done",
            Self::Blocked => "blocked",
            Self::Unknown => "unknown",
        }
    }
}

pub fn list_spec_dirs(specs_dir: &Path) -> Result<Vec<PathBuf>> {
    if !specs_dir.is_dir() {
        return Ok(vec![]);
    }
    let mut dirs = vec![];
    for entry in fs::read_dir(specs_dir)
        .with_context(|| format!("failed to read {}", specs_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            dirs.push(path);
        }
    }
    dirs.sort();
    Ok(dirs)
}

pub fn get_spec_name(spec_dir: &Path) -> String {
    spec_dir
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown-spec".to_string())
}

pub fn list_task_files(spec_dir: &Path) -> Vec<PathBuf> {
    let mut files = vec![];
    let tasks_dir = spec_dir.join("tasks");
    if !tasks_dir.is_dir() {
        return files;
    }
    if let Ok(rd) = fs::read_dir(tasks_dir) {
        for entry in rd.flatten() {
            let p = entry.path();
            if p.extension().is_some_and(|ext| ext == "md") {
                files.push(p);
            }
        }
    }
    files.sort();
    files
}

pub fn get_task_status(task_file: &Path) -> TaskStatus {
    let re = Regex::new(r"^\s*>?\s*Status:\s*(.+?)\s*$").expect("valid regex");
    let Ok(content) = fs::read_to_string(task_file) else {
        return TaskStatus::Unknown;
    };
    for line in content.lines() {
        if let Some(caps) = re.captures(line) {
            return TaskStatus::from_str(caps.get(1).map(|m| m.as_str()).unwrap_or_default());
        }
    }
    TaskStatus::Unknown
}

pub fn get_task_name(task_file: &Path) -> String {
    let Ok(content) = fs::read_to_string(task_file) else {
        return task_file.display().to_string();
    };
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("# ") {
            return rest.trim().to_string();
        }
    }
    task_file
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| task_file.display().to_string())
}

pub fn set_task_status(task_file: &Path, new_status: TaskStatus) -> Result<()> {
    let content = fs::read_to_string(task_file)
        .with_context(|| format!("failed to read {}", task_file.display()))?;
    let re = Regex::new(r"^(\s*>?\s*Status:\s*).*$").expect("valid regex");
    let mut replaced = false;
    let mut out = String::with_capacity(content.len() + 32);

    for line in content.lines() {
        if !replaced && re.is_match(line) {
            out.push_str(&format!("> Status: {}\n", new_status.as_str()));
            replaced = true;
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }

    if !replaced {
        out.push_str(&format!("\n> Status: {}\n", new_status.as_str()));
    }

    fs::write(task_file, out)
        .with_context(|| format!("failed to write {}", task_file.display()))?;
    Ok(())
}

pub fn count_status(spec_dir: &Path, status: TaskStatus) -> usize {
    list_task_files(spec_dir)
        .into_iter()
        .filter(|f| get_task_status(f) == status)
        .count()
}

pub fn count_total(spec_dir: &Path) -> usize {
    list_task_files(spec_dir).len()
}

pub fn count_remaining(spec_dir: &Path) -> usize {
    list_task_files(spec_dir)
        .into_iter()
        .filter(|f| get_task_status(f) != TaskStatus::Done)
        .count()
}

pub fn count_active(spec_dir: &Path) -> usize {
    list_task_files(spec_dir)
        .into_iter()
        .filter(|f| {
            matches!(
                get_task_status(f),
                TaskStatus::Pending | TaskStatus::InProgress | TaskStatus::InReview
            )
        })
        .count()
}

pub fn status_signature(spec_dir: &Path) -> String {
    let mut signature = String::new();
    for file in list_task_files(spec_dir) {
        let name = file
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        signature.push_str(&name);
        signature.push(':');
        signature.push_str(get_task_status(&file).as_str());
        signature.push(';');
    }
    signature
}

pub fn find_next_task(spec_dir: &Path) -> Option<PathBuf> {
    for f in list_task_files(spec_dir) {
        if get_task_status(&f) == TaskStatus::Pending {
            return Some(f);
        }
    }
    None
}

pub fn find_open_task(spec_dir: &Path) -> Option<PathBuf> {
    for f in list_task_files(spec_dir) {
        if matches!(
            get_task_status(&f),
            TaskStatus::Pending | TaskStatus::InProgress | TaskStatus::InReview
        ) {
            return Some(f);
        }
    }
    None
}

pub fn resolve_spec_dir(specs_dir: &Path, explicit_spec: Option<&str>) -> Result<PathBuf> {
    if let Some(path) = explicit_spec {
        let p = PathBuf::from(path);
        if !p.is_dir() {
            return Err(anyhow!("spec directory does not exist: {}", p.display()));
        }
        return Ok(p);
    }

    let all_specs = list_spec_dirs(specs_dir)?;
    if all_specs.is_empty() {
        return Err(anyhow!(
            "no spec directories found under {}",
            specs_dir.display()
        ));
    }

    let active_specs: Vec<PathBuf> = all_specs
        .iter()
        .filter(|p| count_active(p) > 0)
        .cloned()
        .collect();

    if active_specs.len() == 1 {
        return Ok(active_specs[0].clone());
    }
    if active_specs.len() > 1 {
        return Err(anyhow!(
            "multiple active specs detected; pass --spec explicitly"
        ));
    }

    if all_specs.len() == 1 {
        eprintln!(
            "  ⚠ No active tasks detected. Using the only available spec: {}",
            all_specs[0].display()
        );
        return Ok(all_specs[0].clone());
    }

    if io::stdin().is_terminal() && io::stdout().is_terminal() {
        eprintln!("  ⚠ No active specs found. Select a spec to run:");
        for (i, spec) in all_specs.iter().enumerate() {
            eprintln!(
                "  → [{}] {} ({}/{})",
                i + 1,
                get_spec_name(spec),
                count_status(spec, TaskStatus::Done),
                count_total(spec)
            );
        }
        eprint!("\n  Enter spec number (or press Enter to cancel): ");
        io::stderr().flush().ok();
        let mut buf = String::new();
        io::stdin().read_line(&mut buf).ok();
        let v = buf.trim();
        if let Ok(idx) = v.parse::<usize>() {
            if idx >= 1 && idx <= all_specs.len() {
                return Ok(all_specs[idx - 1].clone());
            }
        }
    }

    Err(anyhow!(
        "no active specs found (no pending/in-progress/in-review tasks). pass --spec <path>"
    ))
}
