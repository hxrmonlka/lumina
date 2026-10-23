use std::process::ExitCode;

use crate::error::{usage, Result};
use crate::targets::{self, Target, TARGETS};
use crate::{flake, host, location};

const REV_ATOM: &str = "self/rev";

enum Step {
    Rev,
    File(&'static Target),
}

const USAGE: &str = "\
Usage: lumina sync [--loc <path>] <category/name>...

Sync each target into the local Alice copy.
The target self/rev updates the lumina input in the flake.lock of the local Alice copy.
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
        return usage("no target. Run 'lumina sync --list'.");
    }

    let host = host::detect();
    let mut steps = Vec::new();

    for atom in atoms {
        if atom == REV_ATOM {
            steps.push(Step::Rev);
            continue;
        }

        let Some(target) = targets::find(atom) else {
            return usage(format!("unknown target '{atom}'. Run 'lumina sync --list'."));
        };
        target.check_host(&host)?;
        steps.push(Step::File(target));
    }

    let root = location::resolve(loc)?;

    for step in steps {
        match step {
            Step::Rev => flake::update_lock(&root)?,
            Step::File(target) => {
                target.run(&root)?;
            }
        }
    }

    Ok(ExitCode::SUCCESS)
}

fn print_list() {
    let width = TARGETS
        .iter()
        .map(|target| target.atom.len())
        .chain([REV_ATOM.len()])
        .max()
        .unwrap_or(0);

    println!("{REV_ATOM:<width$}  all");

    for target in TARGETS {
        println!("{:<width$}  {}", target.atom, target.hosts.join(", "));
    }
}
