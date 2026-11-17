//! Integration tests that run the real `lumina` binary.
//!
//! Only host-independent paths are exercised here: target resolution and host
//! gating depend on the machine the tests run on, so the full obsidian
//! installation flow is covered by the unit tests in `src/obsidian.rs` and
//! `src/sync.rs` instead.

use std::process::{Command, Output};

fn lumina() -> Command {
    Command::new(env!("CARGO_BIN_EXE_lumina"))
}

fn run(args: &[&str]) -> Output {
    lumina().args(args).output().expect("failed to run lumina")
}

fn stderr_of(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn help_prints_usage() {
    for flag in ["-h", "--help"] {
        let output = run(&[flag]);
        assert!(output.status.success(), "exit status for {flag}");
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(stdout.contains("Usage: lumina"));
        assert!(stdout.contains("sync"));
    }
}

#[test]
fn version_prints_version() {
    let output = run(&["--version"]);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.starts_with("lumina "));
}

#[test]
fn unknown_command_fails_with_usage() {
    let output = run(&["bogus"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr_of(&output).contains("unknown command 'bogus'"));
}

#[test]
fn sync_without_targets_fails() {
    let output = run(&["sync"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr_of(&output).contains("no target"));
}

#[test]
fn sync_rejects_unknown_target() {
    let output = run(&["sync", "bogus/name"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr_of(&output).contains("unknown target 'bogus/name'"));
}

#[test]
fn sync_rejects_vault_without_obsidian_target() {
    let output = run(&["sync", "--vault", "/tmp/whatever"]);
    assert_eq!(output.status.code(), Some(2));
    let stderr = stderr_of(&output);
    assert!(stderr.contains("no target"), "unexpected stderr: {stderr}");
}

#[test]
fn sync_rejects_orphan_vault_flag() {
    // --list short-circuits before validation.
    let output = run(&["sync", "--list", "--vault", "/tmp/whatever"]);
    assert!(output.status.success());

    // An existing target together with --vault must be rejected before any
    // filesystem work happens, on every host.
    let output = run(&["sync", "self/rev", "--vault", "/tmp/whatever"]);
    let stderr = stderr_of(&output);
    assert!(
        stderr.contains("--vault is only used with"),
        "unexpected stderr: {stderr}"
    );
}

#[test]
fn sync_lists_all_targets() {
    let output = run(&["sync", "--list"]);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("self/rev"));
    assert!(stdout.contains("app/obsidian-matugen"));
    assert!(stdout.contains("settings/dms"));
}

#[test]
fn sync_help_documents_the_vault_interface() {
    let output = run(&["sync", "--help"]);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("--vault"));
    assert!(stdout.contains("--enable"));
    assert!(stdout.contains("--force"));
    assert!(stdout.contains("app/obsidian-matugen"));
}
