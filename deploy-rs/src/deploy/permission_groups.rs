// deploy/permission_groups.rs - Permission group deployment logic

use crate::config::{apply_profile_overrides, resolve_permission_config};
use std::path::{Path, PathBuf};

/// Process all permission groups in permissions/. Returns list of seen names.
#[allow(clippy::too_many_arguments)]
pub fn deploy_permission_groups(
    permissions_dir: &Path,
    repo_root: &Path,
    profile_data: &serde_json::Value,
    profile_new_items: &mut Vec<String>,
    include: &[String],
    exclude: &[String],
    dry_run: bool,
    deployed_configs: &mut Vec<PathBuf>,
) -> Vec<String> {
    let mut seen = Vec::new();

    let mut entries: Vec<PathBuf> = std::fs::read_dir(permissions_dir)
        .ok()
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| {
                    p.extension().map(|e| e == "json").unwrap_or(false)
                        && !p
                            .file_name()
                            .unwrap()
                            .to_string_lossy()
                            .ends_with(".local.json")
                })
                .collect()
        })
        .unwrap_or_default();
    entries.sort();

    for base_file in entries {
        let group_name = base_file.file_stem().unwrap().to_string_lossy().to_string();
        seen.push(group_name.clone());

        if is_filtered_out(&group_name, include, exclude) {
            println!("  Skipped: {} (filtered out)", group_name);
            continue;
        }

        let config = resolve_permission_config(&base_file, repo_root);
        let config = apply_profile_overrides(config, profile_data, "permissions", &group_name);

        // Track new items for profile drift
        if !profile_data.is_null()
            && profile_data.is_object()
            && !profile_data.as_object().unwrap().is_empty()
        {
            let in_profile = profile_data
                .get("permissions")
                .and_then(|v| v.as_object())
                .map(|m| m.contains_key(&group_name))
                .unwrap_or(false);
            if !in_profile {
                profile_new_items.push(format!("{} (permissions)", group_name));
            }
        }

        if !config.enabled {
            println!("  Skipped: {} (disabled)", group_name);
            continue;
        }

        deployed_configs.push(base_file.clone());
        let local_file = base_file
            .parent()
            .unwrap()
            .join(format!("{}.local.json", group_name));
        if local_file.exists() {
            deployed_configs.push(local_file);
        }

        if dry_run {
            println!("  > Include: {}", group_name);
        } else {
            println!("  Included: {}", group_name);
        }
    }

    seen
}

fn is_filtered_out(name: &str, include: &[String], exclude: &[String]) -> bool {
    if !include.is_empty() {
        return !include.iter().any(|i| i == name);
    }
    if !exclude.is_empty() {
        return exclude.iter().any(|e| e == name);
    }
    false
}
