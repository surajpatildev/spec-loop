use std::env;
use std::io::{self, IsTerminal};

pub struct Ui {
    color: bool,
    unicode: bool,
}

#[derive(Clone, Copy)]
struct Symbols {
    ok: &'static str,
    fail: &'static str,
    warn: &'static str,
    phase: &'static str,
    arrow: &'static str,
    diamond: &'static str,
    box_tl: &'static str,
    box_tr: &'static str,
    box_bl: &'static str,
    box_br: &'static str,
    box_h: &'static str,
    box_v: &'static str,
    bar_full: &'static str,
    bar_empty: &'static str,
}

impl Ui {
    pub fn new() -> Self {
        let color = io::stdout().is_terminal() && env::var_os("NO_COLOR").is_none();
        let locale = env::var("LC_ALL")
            .ok()
            .or_else(|| env::var("LC_CTYPE").ok())
            .or_else(|| env::var("LANG").ok())
            .unwrap_or_default()
            .to_lowercase();
        let unicode = locale.contains("utf-8") || locale.contains("utf8");
        Self { color, unicode }
    }

    fn symbols(&self) -> Symbols {
        if self.unicode {
            Symbols {
                ok: "✓",
                fail: "✗",
                warn: "⚠",
                phase: "●",
                arrow: "→",
                diamond: "◆",
                box_tl: "╭",
                box_tr: "╮",
                box_bl: "╰",
                box_br: "╯",
                box_h: "─",
                box_v: "│",
                bar_full: "█",
                bar_empty: "░",
            }
        } else {
            Symbols {
                ok: "[OK]",
                fail: "[FAIL]",
                warn: "[WARN]",
                phase: "*",
                arrow: "->",
                diamond: "+",
                box_tl: "+",
                box_tr: "+",
                box_bl: "+",
                box_br: "+",
                box_h: "-",
                box_v: "|",
                bar_full: "#",
                bar_empty: ".",
            }
        }
    }

    fn style(&self, code: &'static str, text: &str) -> String {
        if self.color {
            format!("\x1b[{}m{}\x1b[0m", code, text)
        } else {
            text.to_string()
        }
    }

    pub fn dim(&self, text: &str) -> String {
        self.style("2", text)
    }

    pub fn bold(&self, text: &str) -> String {
        self.style("1", text)
    }

    pub fn print_header(&self, version: &str) {
        println!();
        println!(
            "  {} {}",
            self.bold("spec-loop"),
            self.dim(&format!("v{}", version))
        );
    }

    pub fn separator(&self, label: &str, width: usize) {
        let s = self.symbols();
        let base = format!("{}{} {} ", s.box_h, s.box_h, label);
        let rem = width.saturating_sub(label.len() + 5);
        let pad = s.box_h.repeat(rem);
        println!();
        println!("  {}", self.dim(&format!("{}{}", base, pad)));
    }

    pub fn phase(&self, label: &str) {
        let s = self.symbols();
        println!();
        println!("  {} {}", self.style("34", s.phase), self.bold(label));
    }

    pub fn step_info(&self, message: &str) {
        let s = self.symbols();
        println!("      {} {}", self.style("34", s.arrow), message);
    }

    pub fn step_ok(&self, message: &str) {
        let s = self.symbols();
        println!("      {} {}", self.style("32", s.ok), message);
    }

    pub fn step_warn(&self, message: &str) {
        let s = self.symbols();
        println!("      {} {}", self.style("33", s.warn), message);
    }

    pub fn step_error(&self, message: &str) {
        let s = self.symbols();
        eprintln!("      {} {}", self.style("31", s.fail), message);
    }

    pub fn task_complete(&self, task_name: &str, remaining: usize) {
        let s = self.symbols();
        println!();
        println!(
            "  {} {} {} {} remaining",
            self.style("32", s.ok),
            self.bold(task_name),
            self.dim(s.arrow),
            self.dim(&remaining.to_string())
        );
    }

    pub fn box_header(&self, label: &str, width: usize) {
        let s = self.symbols();
        let inner = width.saturating_sub(2);
        let rem = inner.saturating_sub(label.len() + 3);
        let pad = s.box_h.repeat(rem);
        println!();
        println!(
            "  {}",
            self.style(
                "36",
                &format!("{}{} {} {}{}", s.box_tl, s.box_h, label, pad, s.box_tr)
            )
        );
    }

    pub fn box_line(&self, content: &str, width: usize) {
        let s = self.symbols();
        let inner = width.saturating_sub(2);
        let visible_len = content.chars().count();
        let pad = if visible_len < inner {
            " ".repeat(inner - visible_len)
        } else {
            String::new()
        };
        println!(
            "  {}{}{}",
            self.style("36", s.box_v),
            format!("{}{}", content, pad),
            self.style("36", s.box_v)
        );
    }

    pub fn box_empty(&self, width: usize) {
        self.box_line("", width);
    }

    pub fn box_footer(&self, width: usize) {
        let s = self.symbols();
        let inner = width.saturating_sub(2);
        let line = s.box_h.repeat(inner);
        println!(
            "  {}",
            self.style("36", &format!("{}{}{}", s.box_bl, line, s.box_br))
        );
    }

    pub fn progress_bar(&self, current: usize, total: usize, width: usize, label: &str) -> String {
        if total == 0 {
            return format!("0/0 {}", label);
        }
        let s = self.symbols();
        let filled = width * current / total;
        let empty = width.saturating_sub(filled);
        let bar = format!("{}{}", s.bar_full.repeat(filled), s.bar_empty.repeat(empty));
        format!("{} {}/{} {}", bar, current, total, label)
    }

    pub fn diamond(&self) -> &'static str {
        self.symbols().diamond
    }

    pub fn arrow(&self) -> &'static str {
        self.symbols().arrow
    }
}
