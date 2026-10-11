use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const DOTFILES_VAR: &str = "ALICE_DOTFILES";
const FLAKE_INPUT: &str = "lumina";

const USAGE: &str = "\
Usage: lumina <command> [options]

Commands:
  sync    Update the lumina input in the flake.lock of the local Alice copy

Options:
  -h, --help       Print this help
  -V, --version    Print the version
";

const SYNC_USAGE: &str = "\
Usage: lumina sync [--loc <path>]

Update the lumina input in the flake.lock of the local Alice copy.
You can run this command from any directory.

Options:
      --loc <path>    Path to the local Alice copy. Overrides ALICE_DOTFILES.
  -h, --help          Print this help

Environment:
  ALICE_DOTFILES      Path to the local Alice copy.
";

enum Failure {
    Usage(String),
    Runtime(String),
}

fn main() -> ExitCode {
    let args = match env::args_os()
        .skip(1)
        .map(|arg| arg.into_string())
        .collect::<Result<Vec<String>, _>>()
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

fn run(args: &[String]) -> Result<ExitCode, Failure> {
    match args.first().map(String::as_str) {
        None | Some("-h" | "--help" | "help") => {
            print!("{USAGE}");
            Ok(ExitCode::SUCCESS)
        }
        Some("-V" | "--version") => {
            println!("lumina {VERSION}");
            Ok(ExitCode::SUCCESS)
        }
        Some("sync") => sync(&args[1..]),
        Some(other) => Err(Failure::Usage(format!("unknown command '{other}'."))),
    }
}

fn sync(args: &[String]) -> Result<ExitCode, Failure> {
    let mut loc: Option<String> = None;
    let mut iter = args.iter();

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{SYNC_USAGE}");
                return Ok(ExitCode::SUCCESS);
            }
            "--loc" => match iter.next() {
                Some(value) => loc = Some(value.clone()),
                None => return Err(Failure::Usage("--loc needs a path.".to_string())),
            },
            other => match other.strip_prefix("--loc=") {
                Some(value) => loc = Some(value.to_string()),
                None => return Err(Failure::Usage(format!("unknown option '{other}'."))),
            },
        }
    }

    let dir = resolve_location(loc)?;
    update_lock(&dir)
}

fn resolve_location(flag: Option<String>) -> Result<PathBuf, Failure> {
    let raw = match flag {
        Some(value) => value,
        None => env::var(DOTFILES_VAR).unwrap_or_default(),
    };

    if raw.trim().is_empty() {
        return Err(Failure::Usage(format!(
            "no Alice location. Set {DOTFILES_VAR} or pass --loc <path>."
        )));
    }

    let expanded = expand_home(raw.trim());
    let dir = fs::canonicalize(&expanded).map_err(|error| {
        Failure::Runtime(format!("cannot open {}: {error}", expanded.display()))
    })?;

    if !dir.is_dir() {
        return Err(Failure::Runtime(format!(
            "{} is not a directory.",
            dir.display()
        )));
    }

    if !dir.join("flake.nix").is_file() {
        return Err(Failure::Runtime(format!(
            "{} has no flake.nix. Use the root directory of Alice.",
            dir.display()
        )));
    }

    Ok(dir)
}

fn expand_home(raw: &str) -> PathBuf {
    let rest = match raw {
        "~" => Some(""),
        _ => raw.strip_prefix("~/"),
    };

    match (rest, env::var_os("HOME")) {
        (Some(""), Some(home)) => PathBuf::from(home),
        (Some(rest), Some(home)) => PathBuf::from(home).join(rest),
        _ => PathBuf::from(raw),
    }
}

fn update_lock(dir: &Path) -> Result<ExitCode, Failure> {
    eprintln!("lumina: updating '{FLAKE_INPUT}' in {}", dir.display());

    let status = Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "flake",
            "update",
            FLAKE_INPUT,
            "--flake",
        ])
        .arg(dir)
        .env(DOTFILES_VAR, dir)
        .status()
        .map_err(|error| match error.kind() {
            ErrorKind::NotFound => Failure::Runtime("cannot find nix in PATH.".to_string()),
            _ => Failure::Runtime(format!("cannot run nix: {error}")),
        })?;

    Ok(match status.code() {
        Some(0) => ExitCode::SUCCESS,
        Some(code) => ExitCode::from(u8::try_from(code).unwrap_or(1)),
        None => ExitCode::FAILURE,
    })
}
