use std::process::ExitCode;

use crate::error::{usage, Result};
use crate::targets::{self, TARGETS};
use crate::{flake, host, location};

const USAGE: &str = "\
Usage: lumina sync [--loc <path>] [<category/name>...]

Without targets, update the lumina input in the flake.lock of the local Alice copy.
With targets, sync each target into the local Alice copy.
You can run this command from any directory.

Options:
      --loc <path>    Path to the local Alice copy. Overrides ALICE_DOTFILES.
      --list          Print all targets and the hosts that support them.
  -h, --help          Print this help

Environment:
  ALICE_DOTFILES      Path to the local Alice copy.
";

pub fn run(args: &[String]) -> Result<ExitCode> {
    let mut loc: Option<String> = None;
    let mut list = false;
    let mut atoms: Vec<&str> = Vec::new();
    let mut iter = args.iter();

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{USAGE}");
                return Ok(ExitCode::SUCCESS);
            }
            "--list" => list = true,
            "--loc" => match iter.next() {
                Some(value) => loc = Some(value.clone()),
                None => return usage("--loc needs a path."),
            },
            other => {
                if let Some(value) = other.strip_prefix("--loc=") {
                    loc = Some(value.to_string());
                } else if other.starts_with('-') {
                    return usage(format!("unknown option '{other}'."));
                } else {
                    atoms.push(other);
                }
            }
        }
    }

    if list {
        print_list();
        return Ok(ExitCode::SUCCESS);
    }

    if atoms.is_empty() {
        let dir = location::resolve(loc)?;
        return flake::update_lock(&dir);
    }

    let host = host::detect();
    let mut selected = Vec::new();

    for atom in atoms {
        let Some(target) = targets::find(atom) else {
            return usage(format!("unknown target '{atom}'. Run 'lumina sync --list'."));
        };
        target.check_host(&host)?;
        selected.push(target);
    }

    let root = location::resolve(loc)?;

    for target in selected {
        target.run(&root)?;
    }

    Ok(ExitCode::SUCCESS)
}

fn print_list() {
    let width = TARGETS.iter().map(|target| target.atom.len()).max().unwrap_or(0);

    for target in TARGETS {
        println!("{:<width$}  {}", target.atom, target.hosts.join(", "));
    }
}
