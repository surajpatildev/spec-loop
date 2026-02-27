use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Command, Stdio};

use crate::config::Config;
use crate::util::{format_cost, format_duration};

#[derive(Debug, Clone)]
pub struct ClaudeResult {
    pub output_text: String,
    pub cost_usd: f64,
    pub duration_ms: u64,
    pub claude_session_id: String,
}

pub fn run_claude(
    prompt: &str,
    cfg: &Config,
    dry_run: bool,
    verbose: bool,
) -> Result<ClaudeResult> {
    if dry_run {
        return Ok(simulate(prompt));
    }

    let mut cmd = Command::new(&cfg.claude_bin);
    cmd.env_remove("CLAUDECODE")
        .arg("--dangerously-skip-permissions")
        .arg("--print")
        .arg("--output-format")
        .arg("stream-json")
        .arg("--verbose")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());

    if !cfg.claude_model.is_empty() {
        cmd.arg("--model").arg(&cfg.claude_model);
    }

    if !cfg.claude_extra_args.is_empty() {
        for arg in cfg.claude_extra_args.split_whitespace() {
            cmd.arg(arg);
        }
    }

    let mut child = cmd
        .spawn()
        .with_context(|| format!("failed to start {}", cfg.claude_bin))?;

    {
        let mut stdin = child.stdin.take().context("failed to open stdin")?;
        stdin
            .write_all(prompt.as_bytes())
            .context("failed writing prompt")?;
    }

    let stdout = child.stdout.take().context("failed to open stdout")?;
    let reader = BufReader::new(stdout);
    let mut lines = Vec::new();
    let mut stream_tools = 0_u32;
    let cwd = std::env::current_dir().ok();
    let mut last_bash_tool_id = String::new();

    for line in reader.lines() {
        let line = line.context("failed to read claude stream")?;
        if line.trim().is_empty() {
            continue;
        }
        stream_tools = stream_tools.saturating_add(render_stream_event(
            &line,
            verbose,
            stream_tools,
            &mut last_bash_tool_id,
            cwd.as_deref(),
        ));
        lines.push(line);
    }

    let status = child.wait().context("failed waiting for claude")?;
    if !status.success() {
        return Err(anyhow!("claude failed with status {}", status));
    }

    Ok(parse_stream(&lines))
}

fn render_stream_event(
    line: &str,
    verbose: bool,
    current_tool_count: u32,
    last_bash_tool_id: &mut String,
    cwd: Option<&Path>,
) -> u32 {
    let Ok(v) = serde_json::from_str::<Value>(line) else {
        if verbose {
            println!("      → non-json: {}", trim_single_line(line, 100));
        }
        return 0;
    };

    let event_type = v.get("type").and_then(Value::as_str).unwrap_or("");
    match event_type {
        "system" => {
            let subtype = v.get("subtype").and_then(Value::as_str).unwrap_or("");
            if subtype == "init" {
                let model = v.get("model").and_then(Value::as_str).unwrap_or("unknown");
                let session = v
                    .get("session_id")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown");
                let short = session.chars().take(8).collect::<String>();
                println!("      → session  model={}  id={}", model, short);
            }
            0
        }
        "assistant" => {
            if let Some(content) = v
                .get("message")
                .and_then(|m| m.get("content"))
                .and_then(Value::as_array)
                .and_then(|arr| arr.first())
            {
                let ctype = content.get("type").and_then(Value::as_str).unwrap_or("");
                match ctype {
                    "tool_use" => {
                        let tool_id = content
                            .get("id")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .to_string();
                        let tool_name = content
                            .get("name")
                            .and_then(Value::as_str)
                            .unwrap_or("tool");
                        if is_internal_tool(tool_name) && !verbose {
                            return 0;
                        }
                        let cmd = content
                            .get("input")
                            .and_then(Value::as_object)
                            .and_then(|obj| {
                                obj.get("command")
                                    .or_else(|| obj.get("file_path"))
                                    .or_else(|| obj.get("pattern"))
                            })
                            .and_then(Value::as_str)
                            .unwrap_or("");
                        let cmd = compact_path(cmd, cwd);

                        if tool_name == "Bash" {
                            *last_bash_tool_id = tool_id;
                        } else {
                            last_bash_tool_id.clear();
                        }

                        if cmd.is_empty() {
                            println!("      → {}", tool_name);
                        } else {
                            println!("      → {:<8} {}", tool_name, trim_single_line(&cmd, 80));
                        }
                        1
                    }
                    "thinking" => {
                        println!("      → thinking...");
                        0
                    }
                    "text" => {
                        if verbose {
                            let text = content.get("text").and_then(Value::as_str).unwrap_or("");
                            if !text.trim().is_empty() {
                                println!("      → text: {}", trim_single_line(text, 100));
                            }
                        }
                        0
                    }
                    _ => 0,
                }
            } else {
                0
            }
        }
        "user" => {
            if let Some(content) = v
                .get("message")
                .and_then(|m| m.get("content"))
                .and_then(Value::as_array)
                .and_then(|arr| arr.first())
            {
                if content.get("type").and_then(Value::as_str) == Some("tool_result") {
                    let tool_use_id = content
                        .get("tool_use_id")
                        .and_then(Value::as_str)
                        .unwrap_or_default();
                    let is_error = content
                        .get("is_error")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    if is_error {
                        let msg = extract_tool_result_text(content.get("content"));
                        println!("      → error: {}", trim_single_line(msg, 100));
                    } else if !last_bash_tool_id.is_empty() && tool_use_id == last_bash_tool_id {
                        let msg = extract_tool_result_text(content.get("content"));
                        if msg.trim().is_empty() {
                            println!("      → done");
                        } else {
                            println!("      → {}", trim_single_line(msg, 100));
                        }
                        last_bash_tool_id.clear();
                    }
                }
            }
            0
        }
        "result" => {
            let cost = v
                .get("total_cost_usd")
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            let duration_ms = v.get("duration_ms").and_then(Value::as_u64).unwrap_or(0);
            let dur = format_duration(duration_ms / 1000);
            println!(
                "      ✓ result   {} ◆ {} ◆ {} tools",
                dur,
                format_cost(cost),
                current_tool_count
            );
            0
        }
        _ => 0,
    }
}

fn is_internal_tool(name: &str) -> bool {
    matches!(
        name,
        "TodoWrite"
            | "TodoRead"
            | "AskUserQuestion"
            | "EnterPlanMode"
            | "ExitPlanMode"
            | "EnterWorktree"
    )
}

fn trim_single_line(input: &str, max_len: usize) -> String {
    let trimmed = input
        .replace('\n', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if trimmed.chars().count() > max_len {
        let mut out = String::new();
        for ch in trimmed.chars().take(max_len) {
            out.push(ch);
        }
        out.push('…');
        out
    } else {
        trimmed
    }
}

fn compact_path(input: &str, cwd: Option<&Path>) -> String {
    let mut out = input.to_string();
    if let Some(cwd) = cwd {
        let cwd_str = cwd.to_string_lossy();
        let prefix = format!("{}/", cwd_str);
        if out.contains(&prefix) {
            out = out.replace(&prefix, "");
        }
    }
    out
}

fn extract_tool_result_text(content: Option<&Value>) -> &str {
    if let Some(Value::String(s)) = content {
        return s;
    }
    ""
}

fn parse_stream(lines: &[String]) -> ClaudeResult {
    let mut session_id = String::new();
    let mut output_text = String::new();
    let mut cost = 0.0;
    let mut duration_ms = 0_u64;

    for line in lines {
        if let Ok(v) = serde_json::from_str::<Value>(line) {
            if v.get("type").and_then(Value::as_str) == Some("system")
                && v.get("subtype").and_then(Value::as_str) == Some("init")
            {
                if let Some(s) = v.get("session_id").and_then(Value::as_str) {
                    session_id = s.to_string();
                }
            }
            if v.get("type").and_then(Value::as_str) == Some("result") {
                if session_id.is_empty() {
                    if let Some(s) = v.get("session_id").and_then(Value::as_str) {
                        session_id = s.to_string();
                    }
                }
                if let Some(s) = v.get("result").and_then(Value::as_str) {
                    output_text = s.to_string();
                }
                if let Some(c) = v.get("total_cost_usd").and_then(Value::as_f64) {
                    cost = c;
                }
                if let Some(d) = v.get("duration_ms").and_then(Value::as_u64) {
                    duration_ms = d;
                }
            }
        }
    }

    if output_text.is_empty() {
        output_text = lines.join("\n");
    }

    ClaudeResult {
        output_text,
        cost_usd: cost,
        duration_ms,
        claude_session_id: session_id,
    }
}

fn simulate(prompt: &str) -> ClaudeResult {
    let output_text = if prompt.contains("REVIEW_STATUS:")
        || prompt.contains("independent reviewer")
    {
        "REVIEW_STATUS: PASS\nMUST_FIX_COUNT: 0\nSHOULD_FIX_COUNT: 0\nSUGGESTION_COUNT: 0"
            .to_string()
    } else if prompt.contains("BUILD_STATUS: FIXES_APPLIED") || prompt.contains("failed review") {
        "BUILD_STATUS: FIXES_APPLIED".to_string()
    } else {
        "BUILD_STATUS: COMPLETED_TASK".to_string()
    };

    ClaudeResult {
        output_text,
        cost_usd: 0.0,
        duration_ms: 0,
        claude_session_id: "dry-run-session".to_string(),
    }
}

pub fn parse_kv(output: &str, key: &str) -> Option<String> {
    let prefix = format!("{}:", key);

    for line in output.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix(&prefix) {
            return Some(rest.trim().to_string());
        }
    }

    for line in output.lines() {
        if let Some(pos) = line.find(&prefix) {
            let rest = line[pos + prefix.len()..].trim();
            if !rest.is_empty() {
                return Some(
                    rest.split_whitespace()
                        .next()
                        .unwrap_or_default()
                        .trim()
                        .to_string(),
                );
            }
        }
    }

    None
}

pub fn has_tag(output: &str, tag: &str) -> bool {
    output.contains(&format!("<promise>{}</promise>", tag))
}
