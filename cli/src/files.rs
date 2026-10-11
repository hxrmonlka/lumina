use std::fs;
use std::path::Path;

use crate::error::{runtime, Result};

pub fn write_atomic(dest: &Path, data: &[u8]) -> Result<()> {
    let Some(parent) = dest.parent() else {
        return runtime(format!("{} has no parent directory.", dest.display()));
    };

    if let Err(error) = fs::create_dir_all(parent) {
        return runtime(format!("cannot create {}: {error}", parent.display()));
    }

    let mut name = dest.file_name().unwrap_or_default().to_os_string();
    name.push(".lumina-tmp");
    let tmp = parent.join(name);

    if let Err(error) = fs::write(&tmp, data) {
        return runtime(format!("cannot write {}: {error}", tmp.display()));
    }

    if let Err(error) = fs::rename(&tmp, dest) {
        let _ = fs::remove_file(&tmp);
        return runtime(format!("cannot write {}: {error}", dest.display()));
    }

    Ok(())
}
