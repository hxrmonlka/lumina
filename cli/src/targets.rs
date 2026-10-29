use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde_json::Value;

use crate::error::{runtime, Result};
use crate::files::write_atomic;

pub enum Source {
    HomeFile(&'static str),
    Command {
        program: &'static str,
        args: &'static [&'static str],
        hint: &'static str,
    },
}

pub struct Target {
    pub atom: &'static str,
    pub hosts: &'static [&'static str],
    pub source: Source,
    pub dest: &'static str,
    pub json: bool,
    pub precommit: bool,
}

pub const TARGETS: &[Target] = &[
    Target {
        atom: "settings/dms",
        hosts: &["serpentine"],
        source: Source::Command {
            program: "dms",
            args: &["ipc", "call", "settings", "dump"],
            hint: "Is DMS running?",
        },
        dest: "modules/home/alice/desktop/dms-settings.json",
        json: true,
        precommit: false,
    },
    Target {
        atom: "settings/dms-kdl",
        hosts: &["serpentine"],
        source: Source::HomeFile(".config/niri/dms/colors.kdl"),
        dest: "modules/home/alice/desktop/dms-colors.kdl",
        json: false,
        precommit: true,
    },
    Target {
        atom: "settings/noctalia",
        hosts: &["tanuki"],
        source: Source::Command {
            program: "qs",
            args: &["-c", "noctalia-shell", "ipc", "call", "state", "all"],
            hint: "Is Noctalia running?",
        },
        dest: "modules/home/konoe/desktop/noctalia.json",
        json: true,
        precommit: false,
    },
    Target {
        atom: "settings/noctalia-kdl",
        hosts: &["tanuki"],
        source: Source::HomeFile(".config/niri/noctalia.kdl"),
        dest: "modules/home/konoe/desktop/noctalia.kdl",
        json: false,
        precommit: true,
    },
];

pub fn find(atom: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|target| target.atom == atom)
}

impl Target {
    pub fn available_on(&self, host: &str) -> bool {
        self.hosts.contains(&host)
    }

    pub fn check_host(&self, host: &str) -> Result<()> {
        if self.available_on(host) {
            return Ok(());
        }

        runtime(format!(
            "{} is not available on '{host}'. Available on: {}.",
            self.atom,
            self.hosts.join(", ")
        ))
    }

    pub fn run(&self, root: &Path) -> Result<PathBuf> {
        let (content, origin) = match &self.source {
            Source::HomeFile(relative) => read_home_file(relative)?,
            Source::Command {
                program,
                args,
                hint,
            } => dump(program, args, hint)?,
        };

        if self.json && serde_json::from_str::<Value>(&content).is_err() {
            return runtime(format!("output of {origin} is not valid JSON."));
        }

        let dest = root.join(self.dest);
        write_atomic(&dest, content.as_bytes())?;
        println!("synced: {origin} -> {}", dest.display());

        Ok(dest)
    }
}

fn read_home_file(relative: &str) -> Result<(String, String)> {
    let Some(home) = env::var_os("HOME") else {
        return runtime("HOME is not set.");
    };

    let path = PathBuf::from(home).join(relative);

    if !path.is_file() {
        return runtime(format!("source file not found: {}", path.display()));
    }

    let content = match fs::read_to_string(&path) {
        Ok(content) => content,
        Err(error) => return runtime(format!("cannot read {}: {error}", path.display())),
    };

    if content.is_empty() {
        return runtime(format!("source file is empty: {}", path.display()));
    }

    Ok((content, path.display().to_string()))
}

fn dump(program: &str, args: &[&str], hint: &str) -> Result<(String, String)> {
    let label = format!("{program} {}", args.join(" "));

    let output = Command::new(program)
        .args(args)
        .stderr(Stdio::inherit())
        .output();

    let output = match output {
        Ok(output) => output,
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return runtime(format!("cannot find {program} in PATH."))
        }
        Err(error) => return runtime(format!("cannot run {program}: {error}")),
    };

    if !output.status.success() {
        return runtime(format!("'{label}' failed ({}).", output.status));
    }

    let Ok(text) = String::from_utf8(output.stdout) else {
        return runtime(format!("output of '{label}' is not valid UTF-8."));
    };

    let text = text.trim_end_matches('\n');

    if text.trim().is_empty() {
        return runtime(format!("'{label}' returned nothing. {hint}"));
    }

    Ok((format!("{text}\n"), label))
}
