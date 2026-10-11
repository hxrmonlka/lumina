mod error;
mod files;
mod flake;
mod hook;
mod host;
mod location;
mod sync;
mod targets;

use std::env;
use std::process::ExitCode;

use error::{usage, Failure, Result};

const VERSION: &str = env!("CARGO_PKG_VERSION");

const USAGE: &str = "\
Usage: lumina <command> [options]

Commands:
  sync    Sync settings and the flake.lock of the local Alice copy
  hook    Run a Git hook action

Options:
  -h, --help       Print this help
  -V, --version    Print the version
";

fn main() -> ExitCode {
    let args = match env::args_os()
        .skip(1)
        .map(|arg| arg.into_string())
        .collect::<std::result::Result<Vec<String>, _>>()
    {
        Ok(args) => args,
        Err(_) => {
            eprintln!("lumina: arguments must be valid UTF-8.");
            return ExitCode::from(2);
        }
    };

    match run(&args) {
        Ok(code) => code,
        Err(Failure::Usage(message)) => {
            eprintln!("lumina: {message}");
            eprintln!("Run 'lumina --help' for usage.");
            ExitCode::from(2)
        }
        Err(Failure::Runtime(message)) => {
            eprintln!("lumina: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: &[String]) -> Result<ExitCode> {
    match args.first().map(String::as_str) {
        None | Some("-h" | "--help" | "help") => {
            print!("{USAGE}");
            Ok(ExitCode::SUCCESS)
        }
        Some("-V" | "--version") => {
            println!("lumina {VERSION}");
            Ok(ExitCode::SUCCESS)
        }
        Some("sync") => sync::run(&args[1..]),
        Some("hook") => hook::run(&args[1..]),
        Some(other) => usage(format!("unknown command '{other}'.")),
    }
}
