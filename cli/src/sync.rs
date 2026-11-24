use std::process::ExitCode;

use crate::error::{usage, Result};
use crate::targets::{self, Source, Target, REV_TARGETS, TARGETS};
use crate::{flake, host, location, obsidian};

enum Step {
    Rev(&'static str),
    File(&'static Target),
    Obsidian,
}

const USAGE: &str = "\
Usage: lumina sync [--loc <path>] [--vault <path>...] <category/name>...
       lumina sync --list

Sync each target into the local Alice copy.
The rev targets update one input in the flake.lock of the local Alice copy:
  self/rev         lumina
  shoji/rev        shoji
You can run this command from any directory.

Options:
      --loc <path>     Path to the local Alice copy. Overrides ALICE_DOTFILES.
      --vault <path>   Target Obsidian vault. Repeatable. Only used with app/obsidian-matugen.
      --enable         Add the snippet to each vault's enabled snippets in appearance.json.
      --force          Overwrite the vault snippet even when matugen has rendered it.
      --list           Print all targets and the hosts that support them.
  -h, --help           Print this help

Obsidian:
  app/obsidian-matugen installs the bundled Material 3 matugen template and
  manages <vault>/.obsidian/snippets/obsidian-material3.css. Matugen renders
  the colors: add the printed template entry to your matugen config, then run
  'matugen image <wallpaper>'.
";

struct Invocation<'a> {
    loc: Option<String>,
    list: bool,
    enable: bool,
    force: bool,
    vaults: Vec<String>,
    atoms: Vec<&'a str>,
}

pub fn run(args: &[String]) -> Result<ExitCode> {
    let mut invocation = Invocation {
        loc: None,
        list: false,
        enable: false,
        force: false,
        vaults: Vec::new(),
        atoms: Vec::new(),
    };

    let mut iter = args.iter();

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{USAGE}");
                return Ok(ExitCode::SUCCESS);
            }
            "--list" => invocation.list = true,
            "--enable" => invocation.enable = true,
            "--force" => invocation.force = true,
            "--loc" => match iter.next() {
                Some(value) => invocation.loc = Some(value.clone()),
                None => return usage("--loc needs a path."),
            },
            "--vault" => match iter.next() {
                Some(value) => invocation.vaults.push(value.clone()),
                None => return usage("--vault needs a path."),
            },
            other => {
                if let Some(value) = other.strip_prefix("--loc=") {
                    invocation.loc = Some(value.to_string());
                } else if let Some(value) = other.strip_prefix("--vault=") {
                    invocation.vaults.push(value.to_string());
                } else if other == "--enable=" || other == "--force=" || other == "--list=" {
                    return usage(format!("'{other}' does not take a value."));
                } else if other.starts_with('-') {
                    return usage(format!("unknown option '{other}'."));
                } else {
                    invocation.atoms.push(other);
                }
            }
        }
    }

    execute(&invocation, &host::detect())
}

fn execute(invocation: &Invocation, host: &str) -> Result<ExitCode> {
    if invocation.list {
        print_list();
        return Ok(ExitCode::SUCCESS);
    }

    if invocation.atoms.is_empty() {
        return usage("no target. Run 'lumina sync --list'.");
    }

    let mut steps = Vec::new();

    for atom in &invocation.atoms {
        if let Some(rev) = targets::find_rev(atom) {
            steps.push(Step::Rev(rev.input));
            continue;
        }

        let Some(target) = targets::find(atom) else {
            return usage(format!(
                "unknown target '{atom}'. Run 'lumina sync --list'."
            ));
        };
        target.check_host(host)?;

        steps.push(match target.source {
            Source::Obsidian => Step::Obsidian,
            _ => Step::File(target),
        });
    }

    let obsidian_steps = steps.iter().any(|step| matches!(step, Step::Obsidian));
    obsidian::validate_flags(
        &invocation.vaults,
        invocation.enable,
        invocation.force,
        obsidian_steps,
    )?;

    // Vault targets never resolve the Alice copy; Alice targets never need a
    // vault. The Alice root is only resolved when a step actually needs it.
    let needs_root = steps
        .iter()
        .any(|step| matches!(step, Step::Rev(_) | Step::File(_)));
    let root = match needs_root {
        true => Some(location::resolve(invocation.loc.clone())?),
        false => None,
    };

    for step in steps {
        match step {
            Step::Rev(input) => flake::update_lock(root.as_deref().unwrap(), input)?,
            Step::File(target) => {
                target.run(root.as_deref().unwrap())?;
            }
            Step::Obsidian => {
                obsidian::run(&invocation.vaults, invocation.enable, invocation.force)?;
            }
        }
    }

    Ok(ExitCode::SUCCESS)
}

fn print_list() {
    let width = TARGETS
        .iter()
        .map(|target| target.atom.len())
        .chain(REV_TARGETS.iter().map(|rev| rev.atom.len()))
        .max()
        .unwrap_or(0);

    for rev in REV_TARGETS {
        println!("{:<width$}  all", rev.atom);
    }

    for target in TARGETS {
        println!("{:<width$}  {}", target.atom, target.hosts.join(", "));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::Failure;
    use crate::obsidian::ENV_LOCK;
    use crate::targets::OBSIDIAN_ATOM;
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir(label: &str) -> PathBuf {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = env::temp_dir().join(format!(
            "lumina-sync-test-{label}-{}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn make_vault(label: &str) -> PathBuf {
        let vault = temp_dir(label);
        fs::create_dir_all(vault.join(".obsidian")).unwrap();
        vault
    }

    fn invocation<'a>(atoms: &'a [&'a str], vaults: Vec<String>) -> Invocation<'a> {
        Invocation {
            loc: None,
            list: false,
            enable: false,
            force: false,
            vaults,
            atoms: atoms.to_vec(),
        }
    }

    #[test]
    fn requires_vault_for_obsidian_atom() {
        let invocation = invocation(&[OBSIDIAN_ATOM], Vec::new());
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(matches!(error, Failure::Usage(_)));
        assert!(error.to_string().contains("--vault"));
    }

    #[test]
    fn rejects_vault_without_obsidian_atom() {
        let invocation = invocation(&["settings/dms"], vec!["/tmp/whatever".to_string()]);
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(matches!(error, Failure::Usage(_)));
        assert!(error.to_string().contains("--vault is only used with"));
    }

    #[test]
    fn rejects_enable_without_obsidian_atom() {
        let mut invocation = invocation(&["settings/dms"], Vec::new());
        invocation.enable = true;
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(error.to_string().contains("--enable is only used with"));
    }

    #[test]
    fn rejects_force_without_obsidian_atom() {
        let mut invocation = invocation(&["self/rev"], Vec::new());
        invocation.force = true;
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(error.to_string().contains("--force is only used with"));
    }

    #[test]
    fn rejects_unknown_target() {
        let invocation = invocation(&["bogus/name"], Vec::new());
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(error.to_string().contains("unknown target 'bogus/name'"));
    }

    #[test]
    fn rev_atoms_resolve_to_their_input() {
        assert_eq!(targets::find_rev("self/rev").unwrap().input, "lumina");
        assert_eq!(targets::find_rev("shoji/rev").unwrap().input, "shoji");
        assert!(targets::find_rev("shoji").is_none());
    }

    #[test]
    fn rejects_vault_with_shoji_rev() {
        let invocation = invocation(&["shoji/rev"], vec!["/tmp/whatever".to_string()]);
        let error = execute(&invocation, "ekpyrosis").unwrap_err();
        assert!(matches!(error, Failure::Usage(_)));
        assert!(error.to_string().contains("--vault is only used with"));
    }

    #[test]
    fn rev_atoms_run_on_every_host() {
        let dir = temp_dir("rev-host");

        for host in ["ekpyrosis", "tanuki", "unknown"] {
            let mut invocation = invocation(&["shoji/rev"], Vec::new());
            invocation.loc = Some(dir.display().to_string());
            let error = execute(&invocation, host).unwrap_err();
            assert!(matches!(error, Failure::Runtime(_)));
            assert!(error.to_string().contains("has no flake.nix"));
        }
    }

    #[test]
    fn obsidian_atom_does_not_need_the_alice_root() {
        let _guard = ENV_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        let vault = make_vault("no-alice-root");
        let config_home = temp_dir("no-alice-root-config");

        let saved = env::var_os("XDG_CONFIG_HOME");
        env::set_var("XDG_CONFIG_HOME", &config_home);

        let result = execute(
            &invocation(&[OBSIDIAN_ATOM], vec![vault.display().to_string()]),
            "ekpyrosis",
        );

        match saved {
            Some(value) => env::set_var("XDG_CONFIG_HOME", value),
            None => env::remove_var("XDG_CONFIG_HOME"),
        }

        let _ = result.expect("sync app/obsidian-matugen should succeed");

        let snippet = vault
            .join(".obsidian/snippets")
            .join(obsidian::SNIPPET_NAME);
        assert!(snippet.is_file());
    }

    #[test]
    fn missing_vault_fails_with_diagnostic() {
        let _guard = ENV_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        let config_home = temp_dir("missing-vault-config");
        let missing = temp_dir("missing-vault").join("nope");

        let saved = env::var_os("XDG_CONFIG_HOME");
        env::set_var("XDG_CONFIG_HOME", &config_home);

        let result = execute(
            &invocation(&[OBSIDIAN_ATOM], vec![missing.display().to_string()]),
            "ekpyrosis",
        );

        match saved {
            Some(value) => env::set_var("XDG_CONFIG_HOME", value),
            None => env::remove_var("XDG_CONFIG_HOME"),
        }

        let error = result.unwrap_err();
        assert!(error.to_string().contains("cannot open vault"));
    }
}
