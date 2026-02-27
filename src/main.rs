use clap::{CommandFactory, Parser};

mod circuit_breaker;
mod claude;
mod cli;
mod commands;
mod config;
mod constants;
mod prompts;
mod session;
mod spec;
mod ui;
mod util;

use cli::{Cli, Command};
use constants::{EXIT_ERROR, EXIT_OK, SPECLOOP_VERSION};
use ui::Ui;

fn main() {
    let ui = Ui::new();
    let cli = Cli::parse();

    let result = match cli.command {
        Some(Command::Init(args)) => commands::cmd_init(&args, &ui),
        Some(Command::Run(args)) => commands::cmd_run(&args, &ui),
        Some(Command::Status) => commands::cmd_status(&ui),
        Some(Command::Version) => {
            println!("spec-loop v{}", SPECLOOP_VERSION);
            Ok(EXIT_OK)
        }
        None => {
            let mut cmd = Cli::command();
            cmd.print_help().ok();
            println!();
            Ok(EXIT_OK)
        }
    };

    match result {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            ui.step_error(&err.to_string());
            std::process::exit(EXIT_ERROR);
        }
    }
}
