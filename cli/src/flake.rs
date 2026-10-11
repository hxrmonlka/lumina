use std::io::ErrorKind;
use std::path::Path;
use std::process::{Command, ExitCode};

use crate::error::{runtime, Result};
use crate::location::DOTFILES_VAR;

const FLAKE_INPUT: &str = "lumina";

pub fn update_lock(dir: &Path) -> Result<ExitCode> {
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
        .status();

    let status = match status {
        Ok(status) => status,
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return runtime("cannot find nix in PATH.")
        }
        Err(error) => return runtime(format!("cannot run nix: {error}")),
    };

    Ok(match status.code() {
        Some(0) => ExitCode::SUCCESS,
        Some(code) => ExitCode::from(u8::try_from(code).unwrap_or(1)),
        None => ExitCode::FAILURE,
    })
}
