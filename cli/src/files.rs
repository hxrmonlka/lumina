use std::fs;
use std::io::ErrorKind;
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

/// Write `data` to `dest` unless an identical file is already there.
///
/// Returns `true` when the file was (re)written, `false` when the existing
/// content already matches. Missing parent directories are created.
pub fn write_if_changed(dest: &Path, data: &[u8]) -> Result<bool> {
    match fs::read(dest) {
        Ok(existing) if existing == data => return Ok(false),
        Ok(_) => {}
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => return runtime(format!("cannot read {}: {error}", dest.display())),
    }

    write_atomic(dest, data)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let dir = env::temp_dir().join(format!("lumina-files-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn writes_when_missing() {
        let dir = temp_dir("missing");
        let dest = dir.join("nested").join("out.css");

        assert!(write_if_changed(&dest, b"hello").unwrap());
        assert_eq!(fs::read(&dest).unwrap(), b"hello");
    }

    #[test]
    fn skips_when_identical() {
        let dir = temp_dir("identical");
        let dest = dir.join("out.css");

        assert!(write_if_changed(&dest, b"hello").unwrap());
        assert!(!write_if_changed(&dest, b"hello").unwrap());
        assert_eq!(fs::read(&dest).unwrap(), b"hello");
    }

    #[test]
    fn writes_when_different() {
        let dir = temp_dir("different");
        let dest = dir.join("out.css");

        assert!(write_if_changed(&dest, b"hello").unwrap());
        assert!(write_if_changed(&dest, b"world").unwrap());
        assert_eq!(fs::read(&dest).unwrap(), b"world");
    }
}
