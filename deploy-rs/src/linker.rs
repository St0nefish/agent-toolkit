// linker.rs - Symlink creation and cleanup

use anyhow::Result;
use std::fs;
use std::path::Path;

/// Create or verify a symlink from link -> target.
///
/// Returns "OK" if already correct, "Linked" if created/updated.
pub fn ensure_link(
    link: &Path,
    target: &Path,
    label: &str,
    dry_run: bool,
    for_dir: bool,
) -> Result<&'static str> {
    if !dry_run {
        if let Ok(existing) = fs::read_link(link) {
            if existing == target {
                println!("  OK: {}", label);
                return Ok("OK");
            }
        }
    }

    if dry_run {
        let flag = if for_dir { "-sfn" } else { "-sf" };
        println!("  > ln {} {} {}", flag, target.display(), link.display());
    } else {
        // Create parent directories
        if let Some(parent) = link.parent() {
            fs::create_dir_all(parent)?;
        }
        // Remove existing link/file
        let _ = fs::remove_file(link);
        // On Unix, remove directory symlink too
        let _ = fs::remove_dir(link);

        #[cfg(unix)]
        std::os::unix::fs::symlink(target, link)?;
        #[cfg(not(unix))]
        anyhow::bail!("Symlinks are only supported on Unix");

        println!("  Linked: {}", label);
    }

    Ok("Linked")
}

/// Remove broken symlinks in a directory.
///
/// filter_type: "" (all), "dir" (only dir symlinks)
///
/// For non-"dir" filter types, also cleans subdirectories containing only broken symlinks.
pub fn cleanup_broken_symlinks(directory: &Path, filter_type: &str, dry_run: bool) {
    if !directory.is_dir() {
        return;
    }

    let entries: Vec<_> = match fs::read_dir(directory) {
        Ok(entries) => entries.filter_map(|e| e.ok()).collect(),
        Err(_) => return,
    };

    for entry in &entries {
        let path = entry.path();
        if !path.is_symlink() {
            continue;
        }
        // Check if target exists (broken symlink)
        if path.exists() {
            continue;
        }
        if dry_run {
            println!("  > Would remove broken symlink: {}", path.display());
        } else {
            let _ = fs::remove_file(&path);
            println!("  Cleaned: broken symlink {} (target gone)", path.display());
        }
    }

    // For skills directory (non-"dir" mode), clean subdirs with only broken symlinks
    if filter_type != "dir" {
        let subdirs: Vec<_> = match fs::read_dir(directory) {
            Ok(entries) => entries
                .filter_map(|e| e.ok())
                .filter(|e| {
                    let p = e.path();
                    p.is_dir() && !p.is_symlink()
                })
                .collect(),
            Err(_) => return,
        };

        for subdir_entry in subdirs {
            let subdir = subdir_entry.path();
            let sub_entries: Vec<_> = match fs::read_dir(&subdir) {
                Ok(entries) => entries.filter_map(|e| e.ok()).collect(),
                Err(_) => continue,
            };

            let has_valid = sub_entries.iter().any(|e| {
                let p = e.path();
                p.is_symlink() && p.exists()
            });

            if !has_valid {
                for entry in &sub_entries {
                    let p = entry.path();
                    if p.is_symlink() {
                        if dry_run {
                            println!("  > Would remove broken symlink: {}", p.display());
                        } else {
                            let _ = fs::remove_file(&p);
                            println!("  Cleaned: broken symlink {} (target gone)", p.display());
                        }
                    }
                }
                if dry_run {
                    println!(
                        "  > Would remove empty skills subdirectory: {}",
                        subdir.display()
                    );
                } else {
                    match fs::remove_dir(&subdir) {
                        Ok(_) => {
                            println!("  Cleaned: empty skills subdirectory {}", subdir.display())
                        }
                        Err(_) => {}
                    }
                }
            }
        }
    }
}

/// Return true if a skill is already deployed globally.
pub fn is_globally_deployed(deploy_name: &str, global_skills_base: &Path) -> bool {
    let skill_md = global_skills_base.join(deploy_name).join("SKILL.md");
    skill_md.is_symlink()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_ensure_link_creates_symlink() {
        let tmp = TempDir::new().unwrap();
        let target = tmp.path().join("target_file");
        fs::write(&target, "content").unwrap();

        let link = tmp.path().join("link_file");
        let result = ensure_link(&link, &target, "test", false, false).unwrap();
        assert_eq!(result, "Linked");
        assert!(link.is_symlink());
        assert_eq!(fs::read_link(&link).unwrap(), target);
    }

    #[test]
    fn test_ensure_link_already_correct() {
        let tmp = TempDir::new().unwrap();
        let target = tmp.path().join("target_file");
        fs::write(&target, "content").unwrap();

        let link = tmp.path().join("link_file");
        #[cfg(unix)]
        std::os::unix::fs::symlink(&target, &link).unwrap();

        let result = ensure_link(&link, &target, "test", false, false).unwrap();
        assert_eq!(result, "OK");
    }

    #[test]
    fn test_cleanup_broken_symlinks() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("links");
        fs::create_dir_all(&dir).unwrap();

        // Create a broken symlink
        #[cfg(unix)]
        std::os::unix::fs::symlink("/nonexistent/target", dir.join("broken")).unwrap();

        // Create a valid symlink
        let target = tmp.path().join("valid_target");
        fs::write(&target, "").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(&target, dir.join("valid")).unwrap();

        cleanup_broken_symlinks(&dir, "dir", false);

        // Broken should be removed
        assert!(!dir.join("broken").exists());
        // Valid should remain
        assert!(dir.join("valid").is_symlink());
    }
}
