use clap::{Args, Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(name = "spec-loop", about = "spec-driven autonomous development loop")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Initialize spec-loop in the current project
    Init(InitArgs),
    /// Run build->review->fix loop
    Run(RunArgs),
    /// Show current spec progress
    Status,
    /// Show version
    Version,
}

#[derive(Args, Debug, Clone)]
pub struct RunArgs {
    /// Spec directory (auto-detects if one active)
    #[arg(long)]
    pub spec: Option<String>,
    /// Max task iterations
    #[arg(long = "max-loops")]
    pub max_loops: Option<u32>,
    /// Review-fix retries per task
    #[arg(long = "max-review-fix-loops")]
    pub max_review_fix_loops: Option<u32>,
    /// Max tasks to complete in this run
    #[arg(long = "max-tasks")]
    pub max_tasks: Option<u32>,
    /// Single build+review cycle
    #[arg(long)]
    pub once: bool,
    /// Print commands without executing
    #[arg(long)]
    pub dry_run: bool,
    /// Build only, no review
    #[arg(long)]
    pub skip_review: bool,
    /// Resume last session
    #[arg(long)]
    pub resume: bool,
    /// Full stream output
    #[arg(long)]
    pub verbose: bool,
}

#[derive(Args, Debug, Clone)]
pub struct InitArgs {
    /// Overwrite existing configuration
    #[arg(long)]
    pub force: bool,
    /// Non-interactive (use detection + defaults)
    #[arg(long = "no-wizard")]
    pub no_wizard: bool,
    /// Override verify command
    #[arg(long = "verify-cmd")]
    pub verify_cmd: Option<String>,
    /// Override test command
    #[arg(long = "test-cmd")]
    pub test_cmd: Option<String>,
}
