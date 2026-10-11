use std::env;
use std::fs;
use std::path::PathBuf;

use crate::error::{runtime, usage, Result};

pub const DOTFILES_VAR: &str = "ALICE_DOTFILES";

pub fn resolve(flag: Option<String>) -> Result<PathBuf> {
    let raw = match flag {
        Some(value) => value,
        None => env::var(DOTFILES_VAR).unwrap_or_default(),
    };

    if raw.trim().is_empty() {
        return usage(format!(
            "no Alice location. Set {DOTFILES_VAR} or pass --loc <path>."
        ));
    }

    let expanded = expand_home(raw.trim());
    let dir = match fs::canonicalize(&expanded) {
        Ok(dir) => dir,
        Err(error) => return runtime(format!("cannot open {}: {error}", expanded.display())),
    };

    if !dir.is_dir() {
        return runtime(format!("{} is not a directory.", dir.display()));
    }

    if !dir.join("flake.nix").is_file() {
        return runtime(format!(
            "{} has no flake.nix. Use the root directory of Alice.",
            dir.display()
        ));
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
