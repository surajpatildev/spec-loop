use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::ui::Ui;
use crate::util::now_iso;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CircuitStateFile {
    state: CircuitState,
    failures: u32,
    opened_at: String,
}

pub struct CircuitBreaker {
    path: PathBuf,
    state: CircuitState,
    failures: u32,
    opened_at: String,
}

impl CircuitBreaker {
    pub fn load(session_dir: &Path) -> Result<Self> {
        fs::create_dir_all(session_dir)
            .with_context(|| format!("failed to create {}", session_dir.display()))?;

        let path = session_dir.join(".circuit_breaker.json");
        let mut cb = Self {
            path,
            state: CircuitState::Closed,
            failures: 0,
            opened_at: String::new(),
        };

        if cb.path.exists() {
            let text = fs::read_to_string(&cb.path)
                .with_context(|| format!("failed to read {}", cb.path.display()))?;
            if let Ok(data) = serde_json::from_str::<CircuitStateFile>(&text) {
                cb.state = data.state;
                cb.failures = data.failures;
                cb.opened_at = data.opened_at;
            }
        }

        Ok(cb)
    }

    pub fn check(&mut self, cooldown_minutes: u32, ui: &Ui) -> Result<bool> {
        match self.state {
            CircuitState::Closed | CircuitState::HalfOpen => Ok(true),
            CircuitState::Open => {
                if self.opened_at.is_empty() {
                    ui.step_error("Circuit breaker: OPEN (no timestamp, resetting)");
                    self.state = CircuitState::Closed;
                    self.failures = 0;
                    self.save()?;
                    return Ok(true);
                }

                let Some(opened_at) = parse_iso_epoch(&self.opened_at) else {
                    ui.step_error("Circuit breaker: OPEN (invalid timestamp, resetting)");
                    self.state = CircuitState::Closed;
                    self.failures = 0;
                    self.save()?;
                    return Ok(true);
                };

                let now = Utc::now().timestamp();
                let elapsed_min = ((now - opened_at).max(0) / 60) as u32;
                if elapsed_min >= cooldown_minutes {
                    self.state = CircuitState::HalfOpen;
                    self.save()?;
                    ui.step_warn(
                        "Circuit breaker: HALF_OPEN (cooldown elapsed, allowing one attempt)",
                    );
                    return Ok(true);
                }

                let remaining = cooldown_minutes.saturating_sub(elapsed_min);
                ui.step_error(&format!(
                    "Circuit breaker: OPEN ({}m cooldown remaining)",
                    remaining
                ));
                Ok(false)
            }
        }
    }

    pub fn record(&mut self, made_progress: bool, threshold: u32, ui: &Ui) -> Result<()> {
        if made_progress {
            self.failures = 0;
            self.state = CircuitState::Closed;
        } else {
            self.failures = self.failures.saturating_add(1);
            if self.failures >= threshold {
                self.state = CircuitState::Open;
                self.opened_at = now_iso();
                ui.step_error(&format!(
                    "Circuit breaker: OPEN after {} iterations without progress",
                    self.failures
                ));
            }
        }
        self.save()
    }

    fn save(&self) -> Result<()> {
        let data = CircuitStateFile {
            state: self.state.clone(),
            failures: self.failures,
            opened_at: self.opened_at.clone(),
        };
        let text = serde_json::to_string_pretty(&data)?;
        fs::write(&self.path, text)
            .with_context(|| format!("failed to write {}", self.path.display()))
    }
}

fn parse_iso_epoch(iso: &str) -> Option<i64> {
    DateTime::parse_from_rfc3339(iso)
        .ok()
        .map(|dt| dt.with_timezone(&Utc).timestamp())
}
