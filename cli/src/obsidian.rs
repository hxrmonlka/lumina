use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
#[cfg(test)]
use std::sync::Mutex;

use serde_json::Value;

use crate::error::{runtime, usage, Result};
use crate::files;
use crate::location;

/// The bundled Material 3 matugen template.
///
/// The template lives in `cli/resources/` as a managed Lumina resource instead
/// of a Rust string literal. It is compiled into the binary, so no file is
/// ever read from (or written to) the Nix store at runtime.
pub(crate) const TEMPLATE: &str = include_str!("../resources/obsidian-material3.css");

/// Name of the matugen template file and of the CSS snippet inside the vault.
pub(crate) const SNIPPET_NAME: &str = "obsidian-material3.css";

/// Name of the snippet as Obsidian lists it (without the .css extension).
const SNIPPET_ID: &str = "obsidian-material3";

const MATUGEN_DIR: &str = "matugen";

/// Serializes tests that touch process environment variables.
#[cfg(test)]
pub(crate) static ENV_LOCK: Mutex<()> = Mutex::new(());

const USAGE_FLAGS: &str = "--vault is only used with 'app/obsidian-matugen'.";
const USAGE_ENABLE: &str = "--enable is only used with 'app/obsidian-matugen'.";
const USAGE_FORCE: &str = "--force is only used with 'app/obsidian-matugen'.";
const USAGE_NO_VAULT: &str = "no vault path for 'app/obsidian-matugen'. Pass --vault <path>. Repeat --vault for each vault.";

/// Obsidian keeps its configuration in this directory inside the vault.
const OBSIDIAN_CONFIG_DIR: &str = ".obsidian";

/// Validate flag combinations for the obsidian target.
pub(crate) fn validate_flags(vaults: &[String], enable: bool, force: bool, obsidian: bool) -> Result<()> {
    if enable && !obsidian {
        return usage(USAGE_ENABLE);
    }
    if force && !obsidian {
        return usage(USAGE_FORCE);
    }
    if obsidian {
        if vaults.is_empty() {
            return usage(USAGE_NO_VAULT);
        }
    } else if !vaults.is_empty() {
        return usage(USAGE_FLAGS);
    }
    Ok(())
}

#[derive(Debug)]
enum SnippetOutcome {
    Created,
    Updated,
    Unchanged,
    Protected,
}

/// Resolve the configuration directory matugen reads from.
///
/// Returns the XDG config home itself (`XDG_CONFIG_HOME` when set and
/// non-empty, otherwise `$HOME/.config`); `run_with` appends `matugen`.
/// Both values are passed explicitly to keep the logic testable without
/// mutating process state.
fn config_home(xdg_config_home: Option<&OsString>, home: Option<&OsString>) -> Result<PathBuf> {
    let unset = "cannot locate the matugen config directory. HOME is not set.";

    let base = match xdg_config_home {
        Some(value) if !value.is_empty() => PathBuf::from(value),
        _ => match home {
            Some(home) if !home.is_empty() => PathBuf::from(home).join(".config"),
            _ => return runtime(unset),
        },
    };

    Ok(base)
}

/// Same, but reading the process environment.
fn env_config_home() -> Result<PathBuf> {
    config_home(env::var_os("XDG_CONFIG_HOME").as_ref(), env::var_os("HOME").as_ref())
}

/// Resolve and validate a user-provided vault path.
fn resolve_vault(raw: &str) -> Result<PathBuf> {
    if raw.trim().is_empty() {
        return usage("--vault needs a path to an Obsidian vault.");
    }

    let expanded = location::expand_home(raw.trim());
    let dir = match fs::canonicalize(&expanded) {
        Ok(dir) => dir,
        Err(error) => return runtime(format!("cannot open vault {}: {error}", expanded.display())),
    };

    if !dir.is_dir() {
        return runtime(format!("{} is not a directory.", dir.display()));
    }

    validate_vault(&dir)?;
    Ok(dir)
}

/// Validate that a directory looks like an Obsidian vault.
fn validate_vault(vault: &Path) -> Result<()> {
    let config = vault.join(OBSIDIAN_CONFIG_DIR);

    if !config.is_dir() {
        return runtime(format!(
            "{} has no {OBSIDIAN_CONFIG_DIR} directory. Is {} an Obsidian vault?",
            vault.display(),
            vault.display()
        ));
    }

    Ok(())
}

/// Install the bundled template into the vault's snippet directory.
fn install_snippet(vault: &Path, force: bool) -> Result<SnippetOutcome> {
    let dest = snippet_path(vault);

    let existing = match fs::read_to_string(&dest) {
        Ok(content) => Some(content),
        Err(error) if error.kind() == ErrorKind::NotFound => None,
        Err(error) => return runtime(format!("cannot read {}: {error}", dest.display())),
    };

    let outcome = match existing {
        // The file already carries the current template.
        Some(content) if content == TEMPLATE => SnippetOutcome::Unchanged,
        // The file still holds a matugen template (an older version).
        // Templates always contain {{colors.*}} placeholders; rendered CSS
        // never does, so this never touches matugen's output.
        Some(content) if content.contains("{{colors.") => {
            write_snippet(&dest)?;
            SnippetOutcome::Updated
        }
        // The file was rendered by matugen (or hand-written). Leave it alone
        // unless the caller insists on resetting it.
        Some(_) if force => {
            write_snippet(&dest)?;
            SnippetOutcome::Updated
        }
        Some(_) => SnippetOutcome::Protected,
        // No snippet yet: seed it with the template so the file exists before
        // the first matugen run. Matugen then renders over it.
        None => {
            write_snippet(&dest)?;
            SnippetOutcome::Created
        }
    };

    Ok(outcome)
}

fn write_snippet(dest: &Path) -> Result<()> {
    files::write_atomic(dest, TEMPLATE.as_bytes())
}

/// Add the snippet to the vault's enabled snippets in appearance.json.
///
/// Returns `true` when appearance.json was changed. Run this while Obsidian is
/// closed: a running Obsidian may rewrite the file when it quits.
fn enable_snippet(vault: &Path) -> Result<bool> {
    let path = vault.join(OBSIDIAN_CONFIG_DIR).join("appearance.json");

    let mut root: Value = match fs::read_to_string(&path) {
        Ok(content) => match serde_json::from_str(&content) {
            Ok(value @ Value::Object(_)) => value,
            Ok(_) => {
                return runtime(format!(
                    "{} is not a JSON object. Enable '{SNIPPET_ID}' in Obsidian instead.",
                    path.display()
                ))
            }
            Err(error) => {
                return runtime(format!(
                    "{} is not valid JSON ({error}). Enable '{SNIPPET_ID}' in Obsidian instead.",
                    path.display()
                ))
            }
        },
        Err(error) if error.kind() == ErrorKind::NotFound => Value::Object(serde_json::Map::new()),
        Err(error) => return runtime(format!("cannot read {}: {error}", path.display())),
    };

    let object = root.as_object_mut().unwrap();
    let snippets = object
        .entry("enabledCssSnippets".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));

    let Some(list) = snippets.as_array_mut() else {
        return runtime(format!(
            "{} has a non-array enabledCssSnippets. Enable '{SNIPPET_ID}' in Obsidian instead.",
            path.display()
        ));
    };

    let already = list.iter().any(|entry| entry.as_str() == Some(SNIPPET_ID));
    if already {
        return Ok(false);
    }

    list.push(Value::String(SNIPPET_ID.to_string()));

    let mut rendered = serde_json::to_string_pretty(&root).expect("value is valid JSON");
    rendered.push('\n');
    files::write_atomic(&path, rendered.as_bytes())?;

    Ok(true)
}

/// What the matugen config says about this vault's snippet.
#[derive(Debug, PartialEq)]
enum ConfigState {
    /// No config.toml at all.
    Missing,
    /// Config exists but does not mention the theme at all.
    Unrelated,
    /// Config mentions the theme but not this vault's snippet path.
    OtherVault,
    /// Config renders into this vault's snippet.
    Configured,
}

/// Pure decision helper for `check_matugen_config`, kept side-effect free for
/// tests. `config` is the content of config.toml, if it exists.
fn config_state(config: Option<&str>, template_path: &str, snippet_path: &str) -> ConfigState {
    let Some(config) = config else {
        return ConfigState::Missing;
    };

    let mentions_theme = config.contains(SNIPPET_ID) || config.contains(template_path);
    let mentions_vault = config.contains(snippet_path);

    match (mentions_theme, mentions_vault) {
        (false, _) => ConfigState::Unrelated,
        (true, false) => ConfigState::OtherVault,
        (true, true) => ConfigState::Configured,
    }
}

fn check_matugen_config(templates: &Path, vault: &Path) -> Result<()> {
    let config_path = templates
        .parent()
        .map(|dir| dir.join("config.toml"))
        .unwrap_or_else(|| Path::new(MATUGEN_DIR).join("config.toml"));

    let config = match fs::read_to_string(&config_path) {
        Ok(content) => Some(content),
        Err(error) if error.kind() == ErrorKind::NotFound => None,
        Err(error) => return runtime(format!("cannot read {}: {error}", config_path.display())),
    };

    let template_path = templates.join(SNIPPET_NAME).display().to_string();
    let snippet_path = snippet_path(vault).display().to_string();

    match config_state(config.as_deref(), &template_path, &snippet_path) {
        ConfigState::Configured => {
            println!("matugen: config.toml renders into {snippet_path}");
        }
        state => {
            let reason = match state {
                ConfigState::Missing => "there is no matugen config",
                ConfigState::Unrelated => "it does not mention 'obsidian-material3'",
                ConfigState::OtherVault => {
                    "it renders 'obsidian-material3' into a different vault"
                }
                ConfigState::Configured => unreachable!(),
            };
            eprintln!(
                "lumina: matugen is not wired up for this vault yet: {reason}. Add this entry to {} so matugen renders the colors:",
                config_path.display()
            );
            print_template_hint(templates, vault);
        }
    }

    Ok(())
}

fn print_template_hint(templates: &Path, vault: &Path) {
    println!();
    println!("  [templates.Obsidian]");
    println!("  input_path = '{}'", templates.join(SNIPPET_NAME).display());
    println!("  output_path = '{}'", snippet_path(vault).display());
    println!();
    println!(
        "  For more vaults add one entry per vault (same input_path, its own output_path). Alice manages this file via home-manager, so edit modules/home/alice/programs/matugen.nix."
    );
}

/// Run the obsidian target, reading directories from the environment.
pub(crate) fn run(vaults: &[String], enable: bool, force: bool) -> Result<()> {
    run_with(&env_config_home()?, vaults, enable, force)
}

/// Core implementation with an explicit matugen config directory.
pub(crate) fn run_with(config_home: &Path, vaults: &[String], enable: bool, force: bool) -> Result<()> {
    let templates = config_home.join(MATUGEN_DIR).join("templates");
    let template_dest = templates.join(SNIPPET_NAME);

    let changed = files::write_if_changed(&template_dest, TEMPLATE.as_bytes())?;
    if changed {
        println!("synced: bundled '{SNIPPET_ID}' template -> {}", template_dest.display());
    } else {
        println!("unchanged: {} (bundled template is up to date)", template_dest.display());
    }

    for raw in vaults {
        let vault = resolve_vault(raw)?;

        match install_snippet(&vault, force)? {
            SnippetOutcome::Created => println!(
                "created: {} (waiting for matugen to render it)",
                snippet_path(&vault).display()
            ),
            SnippetOutcome::Updated => println!("updated: {}", snippet_path(&vault).display()),
            SnippetOutcome::Unchanged => println!("unchanged: {}", snippet_path(&vault).display()),
            SnippetOutcome::Protected => println!(
                "kept: {} holds rendered or edited CSS; pass --force to overwrite it with the bundled template",
                snippet_path(&vault).display()
            ),
        }

        if enable {
            let path = vault.join(OBSIDIAN_CONFIG_DIR).join("appearance.json");
            match enable_snippet(&vault)? {
                true => println!("enabled: {SNIPPET_ID} in {}", path.display()),
                false => println!("enabled: {SNIPPET_ID} is already active in {}", path.display()),
            }
        }

        check_matugen_config(&templates, &vault)?;
    }

    Ok(())
}

fn snippet_path(vault: &Path) -> PathBuf {
    vault
        .join(OBSIDIAN_CONFIG_DIR)
        .join("snippets")
        .join(SNIPPET_NAME)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::Failure;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            let id = COUNTER.fetch_add(1, Ordering::SeqCst);
            let dir = env::temp_dir().join(format!(
                "lumina-obsidian-test-{label}-{}-{id}",
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(&dir).unwrap();
            TempDir(dir)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn make_vault(label: &str) -> TempDir {
        let vault = TempDir::new(label);
        fs::create_dir_all(vault.path().join(".obsidian")).unwrap();
        vault
    }

    fn skip_if_root(dir: &Path) -> bool {
        // A probe write into a directory about to be locked down succeeds as
        // root, where permission bits are ignored.
        let probe = dir.join(".lumina-probe");
        if fs::write(&probe, b"x").is_ok() {
            let _ = fs::remove_file(&probe);
            return true;
        }
        false
    }

    // ---- template contents ----

    #[test]
    fn template_defines_both_theme_blocks() {
        assert!(TEMPLATE.contains(".theme-dark {"));
        assert!(TEMPLATE.contains(".theme-light {"));
        assert!(TEMPLATE.contains("--md-sys-color-primary:"));
    }

    #[test]
    fn template_only_uses_known_matugen_tokens() {
        const TOKENS: &[&str] = &[
            "primary",
            "on_primary",
            "primary_container",
            "on_primary_container",
            "inverse_primary",
            "primary_fixed",
            "primary_fixed_dim",
            "on_primary_fixed",
            "on_primary_fixed_variant",
            "secondary",
            "on_secondary",
            "secondary_container",
            "on_secondary_container",
            "secondary_fixed",
            "secondary_fixed_dim",
            "on_secondary_fixed",
            "on_secondary_fixed_variant",
            "tertiary",
            "on_tertiary",
            "tertiary_container",
            "on_tertiary_container",
            "tertiary_fixed",
            "tertiary_fixed_dim",
            "on_tertiary_fixed",
            "on_tertiary_fixed_variant",
            "error",
            "on_error",
            "error_container",
            "on_error_container",
            "surface_dim",
            "surface",
            "surface_tint",
            "surface_bright",
            "surface_container_lowest",
            "surface_container_low",
            "surface_container",
            "surface_container_high",
            "surface_container_highest",
            "on_surface",
            "on_surface_variant",
            "outline",
            "outline_variant",
            "inverse_surface",
            "inverse_on_surface",
            "surface_variant",
            "background",
            "on_background",
            "shadow",
            "scrim",
        ];

        let mut rest = TEMPLATE;
        while let Some(start) = rest.find("{{") {
            let end = rest[start..]
                .find("}}")
                .unwrap_or_else(|| panic!("unclosed placeholder near '{}'", &rest[start..start + 40]));

            let placeholder = &rest[start + 2..start + end];
            assert!(
                placeholder.starts_with("colors."),
                "unknown placeholder syntax: {{{placeholder}}}"
            );

            let parts: Vec<&str> = placeholder.split('.').collect();
            assert_eq!(
                parts.len(),
                4,
                "expected colors.<token>.<scheme>.<format>: {{{placeholder}}}"
            );
            assert_eq!(parts[0], "colors");
            assert!(
                TOKENS.contains(&parts[1]),
                "unknown matugen token '{}' in {{{placeholder}}}",
                parts[1]
            );
            assert!(
                parts[2] == "dark" || parts[2] == "light",
                "unknown scheme '{}' in {{{placeholder}}}",
                parts[2]
            );
            assert_eq!(parts[3], "hex", "only the hex format is used");

            rest = &rest[start + end + 2..];
        }
    }

    #[test]
    fn template_is_plain_css() {
        // The snippet must be plain CSS: balanced braces, no stray markup.
        assert_eq!(TEMPLATE.matches('{').count(), TEMPLATE.matches('}').count());
        assert!(!TEMPLATE.contains("**"));
        assert!(TEMPLATE.starts_with("/*"));
    }

    // ---- vault resolution and validation ----

    #[test]
    fn resolves_existing_vault() {
        let vault = make_vault("resolve");
        let resolved = resolve_vault(vault.path().to_str().unwrap()).unwrap();
        assert_eq!(resolved, fs::canonicalize(vault.path()).unwrap());
    }

    #[test]
    fn expands_home_in_vault_paths() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());

        let vault = make_vault("home");
        let saved = env::var_os("HOME");
        env::set_var("HOME", vault.path());

        let result = resolve_vault("~");

        match saved {
            Some(value) => env::set_var("HOME", value),
            None => env::remove_var("HOME"),
        }

        let resolved = result.unwrap();
        assert_eq!(resolved, fs::canonicalize(vault.path()).unwrap());
    }

    #[test]
    fn rejects_nonexistent_vault() {
        let missing = env::temp_dir().join(format!("lumina-obsidian-missing-{}", std::process::id()));
        let error = resolve_vault(missing.to_str().unwrap()).unwrap_err();
        assert!(matches!(error, Failure::Runtime(_)));
        assert!(error.to_string().contains("cannot open vault"));
    }

    #[test]
    fn rejects_directory_without_vault_marker() {
        let plain = TempDir::new("plain");
        let error = resolve_vault(plain.path().to_str().unwrap()).unwrap_err();
        assert!(error.to_string().contains(".obsidian"));
    }

    #[test]
    fn rejects_empty_vault_argument() {
        let error = resolve_vault("   ").unwrap_err();
        assert!(matches!(error, Failure::Usage(_)));
    }

    // ---- snippet installation ----

    #[test]
    fn install_creates_snippets_directory_and_seeds_template() {
        let vault = make_vault("create");
        let dest = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);

        assert!(!vault.path().join(".obsidian/snippets").exists());

        let outcome = install_snippet(vault.path(), false).unwrap();
        assert!(matches!(outcome, SnippetOutcome::Created));
        assert!(dest.is_file());
        assert_eq!(fs::read_to_string(&dest).unwrap(), TEMPLATE);
    }

    #[test]
    fn install_is_idempotent() {
        let vault = make_vault("idempotent");

        let first = install_snippet(vault.path(), false).unwrap();
        assert!(matches!(first, SnippetOutcome::Created));

        let second = install_snippet(vault.path(), false).unwrap();
        assert!(matches!(second, SnippetOutcome::Unchanged));
    }

    #[test]
    fn install_updates_managed_template_copy() {
        let vault = make_vault("update");
        let dest = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        fs::write(&dest, "{{colors.primary.dark.hex}}").unwrap();

        let outcome = install_snippet(vault.path(), false).unwrap();
        assert!(matches!(outcome, SnippetOutcome::Updated));
        assert_eq!(fs::read_to_string(&dest).unwrap(), TEMPLATE);
    }

    #[test]
    fn install_protects_rendered_snippet() {
        let vault = make_vault("protect");
        let dest = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        let rendered = ".theme-dark { --md-sys-color-primary: #aabbee; }";
        fs::write(&dest, rendered).unwrap();

        let outcome = install_snippet(vault.path(), false).unwrap();
        assert!(matches!(outcome, SnippetOutcome::Protected));
        assert_eq!(fs::read_to_string(&dest).unwrap(), rendered);
    }

    #[test]
    fn install_force_overwrites_rendered_snippet() {
        let vault = make_vault("force");
        let dest = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        fs::write(&dest, ".theme-dark { --md-sys-color-primary: #aabbee; }").unwrap();

        let outcome = install_snippet(vault.path(), true).unwrap();
        assert!(matches!(outcome, SnippetOutcome::Updated));
        assert_eq!(fs::read_to_string(&dest).unwrap(), TEMPLATE);
    }

    #[test]
    fn install_reports_permission_failures() {
        let vault = make_vault("permissions");
        let snippets = vault.path().join(".obsidian/snippets");
        fs::create_dir_all(&snippets).unwrap();

        if skip_if_root(&snippets) {
            return;
        }

        let mut perms = fs::metadata(&snippets).unwrap().permissions();
        perms.set_mode(0o555);
        fs::set_permissions(&snippets, perms).unwrap();

        let error = install_snippet(vault.path(), false).unwrap_err();
        assert!(error.to_string().contains("cannot write"));
    }

    #[test]
    fn install_reports_unreadable_snippet() {
        let vault = make_vault("unreadable");
        let dest = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        fs::write(&dest, "unreadable").unwrap();

        if skip_if_root(dest.parent().unwrap()) {
            return;
        }

        let mut perms = fs::metadata(&dest).unwrap().permissions();
        perms.set_mode(0o000);
        fs::set_permissions(&dest, perms).unwrap();

        let error = install_snippet(vault.path(), false).unwrap_err();
        assert!(error.to_string().contains("cannot read"));
    }

    // ---- enabling ----

    #[test]
    fn enable_creates_appearance_json() {
        let vault = make_vault("enable-create");

        assert!(enable_snippet(vault.path()).unwrap());

        let content = fs::read_to_string(vault.path().join(".obsidian/appearance.json")).unwrap();
        let root: Value = serde_json::from_str(&content).unwrap();
        assert_eq!(
            root["enabledCssSnippets"],
            serde_json::json!(["obsidian-material3"])
        );
    }

    #[test]
    fn enable_merges_into_existing_appearance_json() {
        let vault = make_vault("enable-merge");
        let path = vault.path().join(".obsidian/appearance.json");
        fs::write(
            &path,
            r#"{"baseFontSize": 16, "enabledCssSnippets": ["other"], "theme": "obsidian"}"#,
        )
        .unwrap();

        assert!(enable_snippet(vault.path()).unwrap());

        let root: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(root["baseFontSize"], serde_json::json!(16));
        assert_eq!(root["theme"], serde_json::json!("obsidian"));
        assert_eq!(
            root["enabledCssSnippets"],
            serde_json::json!(["other", "obsidian-material3"])
        );

        // Second run is a no-op.
        assert!(!enable_snippet(vault.path()).unwrap());
    }

    #[test]
    fn enable_rejects_broken_appearance_json() {
        let vault = make_vault("enable-broken");
        let path = vault.path().join(".obsidian/appearance.json");
        fs::write(&path, "not json").unwrap();

        let error = enable_snippet(vault.path()).unwrap_err();
        assert!(error.to_string().contains("not valid JSON"));
    }

    // ---- matugen config diagnostics ----

    #[test]
    fn config_state_without_config_file() {
        let state = config_state(
            None,
            "/t/matugen/templates/obsidian-material3.css",
            "/v/.obsidian/snippets/obsidian-material3.css",
        );
        assert_eq!(state, ConfigState::Missing);
    }

    #[test]
    fn config_state_with_unrelated_config() {
        let state = config_state(
            Some("[templates.starship]\ninput_path = '/x'\n"),
            "/t/matugen/templates/obsidian-material3.css",
            "/v/.obsidian/snippets/obsidian-material3.css",
        );
        assert_eq!(state, ConfigState::Unrelated);
    }

    #[test]
    fn config_state_with_other_vault() {
        let state = config_state(
            Some("[templates.Obsidian]\noutput_path = '/other/.obsidian/snippets/obsidian-material3.css'\n"),
            "/t/matugen/templates/obsidian-material3.css",
            "/v/.obsidian/snippets/obsidian-material3.css",
        );
        assert_eq!(state, ConfigState::OtherVault);
    }

    #[test]
    fn config_state_configured() {
        let state = config_state(
            Some("[templates.Obsidian]\ninput_path = '/t/matugen/templates/obsidian-material3.css'\noutput_path = '/v/.obsidian/snippets/obsidian-material3.css'\n"),
            "/t/matugen/templates/obsidian-material3.css",
            "/v/.obsidian/snippets/obsidian-material3.css",
        );
        assert_eq!(state, ConfigState::Configured);
    }

    // ---- config home resolution ----

    #[test]
    fn config_home_prefers_xdg() {
        let dir = config_home(
            Some(&OsString::from("/xdg/config")),
            Some(&OsString::from("/home/user")),
        )
        .unwrap();
        assert_eq!(dir, PathBuf::from("/xdg/config"));
    }

    #[test]
    fn config_home_falls_back_to_home() {
        let dir = config_home(None, Some(&OsString::from("/home/user"))).unwrap();
        assert_eq!(dir, PathBuf::from("/home/user/.config"));

        let empty = config_home(Some(&OsString::new()), Some(&OsString::from("/home/user"))).unwrap();
        assert_eq!(empty, PathBuf::from("/home/user/.config"));
    }

    #[test]
    fn config_home_errors_without_home() {
        let error = config_home(None, None).unwrap_err();
        assert!(error.to_string().contains("HOME is not set"));
    }

    // ---- full flow ----

    #[test]
    fn run_with_installs_everything() {
        let config_home = TempDir::new("config");
        let vault = make_vault("full");

        run_with(
            config_home.path(),
            &[vault.path().display().to_string()],
            false,
            false,
        )
        .unwrap();

        let template = config_home.path().join("matugen/templates").join(SNIPPET_NAME);
        assert_eq!(fs::read_to_string(&template).unwrap(), TEMPLATE);

        let snippet = vault.path().join(".obsidian/snippets").join(SNIPPET_NAME);
        assert_eq!(fs::read_to_string(&snippet).unwrap(), TEMPLATE);
    }

    #[test]
    fn run_with_enables_snippet_when_asked() {
        let config_home = TempDir::new("config-enable");
        let vault = make_vault("enable-flow");

        run_with(
            config_home.path(),
            &[vault.path().display().to_string()],
            true,
            false,
        )
        .unwrap();

        let root: Value = serde_json::from_str(
            &fs::read_to_string(vault.path().join(".obsidian/appearance.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(
            root["enabledCssSnippets"],
            serde_json::json!(["obsidian-material3"])
        );
    }

    #[test]
    fn run_with_rejects_invalid_vault() {
        let config_home = TempDir::new("config-invalid");
        let missing = env::temp_dir().join(format!("lumina-obsidian-invalid-{}", std::process::id()));

        let error = run_with(
            config_home.path(),
            &[missing.display().to_string()],
            false,
            false,
        )
        .unwrap_err();

        assert!(matches!(error, Failure::Runtime(_)));
    }
}
