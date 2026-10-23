use std::io::ErrorKind;
use std::path::Path;
use std::process::Command;

use crate::error::{runtime, Result};
use crate::location::DOTFILES_VAR;

const FLAKE_INPUT: &str = "lumina";

pub fn update_lock(dir: &Path) -> Result<()> {
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

    if status.success() {
        Ok(())
    } else {
        runtime(format!("'nix flake update' failed ({status})."))
    }
}
