mod cli;
mod config;
mod deploy;
mod discovery;
mod linker;
mod permissions;
mod settings;
mod tui;

use clap::Parser;
use crossterm::tty::IsTty;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // Bare invocation with a TTY → TUI
    // --interactive flag → TUI (even with other flags)
    // Otherwise → headless CLI
    if args.len() == 1 && std::io::stdout().is_tty() {
        match launch_tui() {
            Ok(()) => {}
            Err(e) => {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
    } else {
        let cli_args = cli::Cli::parse();
        if cli_args.interactive {
            match launch_tui() {
                Ok(()) => {}
                Err(e) => {
                    eprintln!("Error: {}", e);
                    std::process::exit(1);
                }
            }
        } else {
            if let Err(e) = cli::run(cli_args) {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
    }
}

fn launch_tui() -> anyhow::Result<()> {
    let repo_root = cli::find_repo_root()?;
    let claude_config_dir = cli::resolve_claude_config_dir();
    tui::run_tui(repo_root, claude_config_dir)
}
