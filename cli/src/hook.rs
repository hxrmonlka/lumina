use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

use crate::error::{runtime, usage, Result};
use crate::targets::TARGETS;
use crate::host;

const USAGE: &str = "\
Usage: lumina hook pre-commit

Run the pre-commit action for this host in the current Git repository.
The action syncs the generated files of this host and stages them.
On a host without an action, the command does nothing.
";

pub fn run(args: &[String]) -> Result<ExitCode> {
    match args.first().map(String::as_str) {
        None | Some("-h" | "--help") => {
            print!("{USAGE}");
            Ok(ExitCode::SUCCESS)
        }
        Some("pre-commit") => pre_commit(),
        Some(other) => usage(format!("unknown hook '{other}'.")),
    }
}

fn pre_commit() -> Result<ExitCode> {
    let host = host::detect();
    let selected: Vec<_> = TARGETS
        .iter()
        .filter(|target| target.precommit && target.available_on(&host))
        .collect();

    if selected.is_empty() {
        return Ok(ExitCode::SUCCESS);
    }

    let root = repo_root()?;

    for target in selected {
        let dest = target.run(&root)?;
        stage(&root, &dest)?;
    }

    Ok(ExitCode::SUCCESS)
}

fn repo_root() -> Result<PathBuf> {
    let output = match Command::new("git").args(["rev-parse", "--show-toplevel"]).output() {
        Ok(output) => output,
        Err(error) => return runtime(format!("cannot run git: {error}")),
    };

    if !output.status.success() {
        return runtime("not inside a Git repository.");
    }

    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if path.is_empty() {
        return runtime("not inside a Git repository.");
    }

    Ok(PathBuf::from(path))
}

fn stage(root: &Path, file: &Path) -> Result<()> {
    let status = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(["add", "--"])
        .arg(file)
        .status();

    match status {
        Ok(status) if status.success() => Ok(()),
        Ok(_) => runtime(format!("cannot stage {}.", file.display())),
        Err(error) => runtime(format!("cannot run git: {error}")),
    }
}
