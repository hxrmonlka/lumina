use std::env;
use std::fs;

pub fn detect() -> String {
    let raw = fs::read_to_string("/proc/sys/kernel/hostname")
        .or_else(|_| fs::read_to_string("/etc/hostname"))
        .ok()
        .or_else(|| env::var("HOSTNAME").ok())
        .unwrap_or_default();

    let name = raw
        .trim()
        .split('.')
        .next()
        .unwrap_or_default()
        .to_lowercase();

    if name.is_empty() {
        "unknown".to_string()
    } else {
        name
    }
}
