// discovery.rs - Item discovery and profile diffing

use crate::config::{apply_profile_overrides, resolve_config, resolve_permission_config};
use serde_json::Value;
use std::path::Path;

/// A discovered item with merged config.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DiscoveredItem {
    pub name: String,
    pub enabled: bool,
    pub scope: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub on_path: Option<bool>,
}

/// Result of discovery across all categories.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DiscoverResult {
    pub repo_root: String,
    pub profiles: Vec<String>,
    pub skills: Vec<DiscoveredItem>,
    pub hooks: Vec<DiscoveredItem>,
    pub mcp: Vec<DiscoveredItem>,
    pub permissions: Vec<DiscoveredItem>,
}

/// Profile diff showing added/removed items.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ProfileDiff {
    pub added: CategoryDiff,
    pub removed: CategoryDiff,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct CategoryDiff {
    pub skills: Vec<String>,
    pub hooks: Vec<String>,
    pub mcp: Vec<String>,
    pub permissions: Vec<String>,
}

/// Discover all deployable items in the repo.
pub fn discover_items(repo_root: &Path, profile_data: &Value) -> DiscoverResult {
    let profiles_dir = repo_root.join(".deploy-profiles");
    let profiles = if profiles_dir.is_dir() {
        let mut names: Vec<String> = std::fs::read_dir(&profiles_dir)
            .ok()
            .map(|entries| {
                entries
                    .filter_map(|e| e.ok())
                    .filter(|e| {
                        e.path()
                            .extension()
                            .map(|ext| ext == "json")
                            .unwrap_or(false)
                    })
                    .map(|e| e.file_name().to_string_lossy().to_string())
                    .collect()
            })
            .unwrap_or_default();
        names.sort();
        names
    } else {
        vec![]
    };

    let skills = discover_category(repo_root, "skills", profile_data, true);
    let hooks = discover_category(repo_root, "hooks", profile_data, true);
    let mcp = discover_category(repo_root, "mcp", profile_data, false);
    let permissions = discover_permissions(repo_root, profile_data);

    DiscoverResult {
        repo_root: repo_root.to_string_lossy().to_string(),
        profiles,
        skills,
        hooks,
        mcp,
        permissions,
    }
}

fn discover_category(
    repo_root: &Path,
    category: &str,
    profile_data: &Value,
    include_on_path: bool,
) -> Vec<DiscoveredItem> {
    let cat_dir = repo_root.join(category);
    if !cat_dir.is_dir() {
        return vec![];
    }

    let mut items = Vec::new();
    let mut entries: Vec<_> = std::fs::read_dir(&cat_dir)
        .ok()
        .map(|entries| entries.filter_map(|e| e.ok()).collect())
        .unwrap_or_default();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();

        let config = resolve_config(&path, repo_root);
        let config = apply_profile_overrides(config, profile_data, category, &name);

        items.push(DiscoveredItem {
            name,
            enabled: config.enabled,
            scope: config.scope,
            on_path: if include_on_path {
                Some(config.on_path)
            } else {
                None
            },
        });
    }

    items
}

fn discover_permissions(repo_root: &Path, profile_data: &Value) -> Vec<DiscoveredItem> {
    let perm_dir = repo_root.join("permissions");
    if !perm_dir.is_dir() {
        return vec![];
    }

    let mut items = Vec::new();
    let mut entries: Vec<_> = std::fs::read_dir(&perm_dir)
        .ok()
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .filter(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    name.ends_with(".json") && !name.ends_with(".local.json")
                })
                .collect()
        })
        .unwrap_or_default();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let path = entry.path();
        let name = path.file_stem().unwrap().to_string_lossy().to_string();

        let config = resolve_permission_config(&path, repo_root);
        let config = apply_profile_overrides(config, profile_data, "permissions", &name);

        items.push(DiscoveredItem {
            name,
            enabled: config.enabled,
            scope: config.scope,
            on_path: None,
        });
    }

    items
}

/// Compare discover output with a deployment profile.
pub fn profile_diff(discover_data: &DiscoverResult, profile_data: &Value) -> ProfileDiff {
    let types = ["skills", "hooks", "mcp", "permissions"];
    let mut added = CategoryDiff {
        skills: vec![],
        hooks: vec![],
        mcp: vec![],
        permissions: vec![],
    };
    let mut removed = CategoryDiff {
        skills: vec![],
        hooks: vec![],
        mcp: vec![],
        permissions: vec![],
    };

    for t in &types {
        let on_disk: Vec<&str> = match *t {
            "skills" => discover_data
                .skills
                .iter()
                .map(|i| i.name.as_str())
                .collect(),
            "hooks" => discover_data
                .hooks
                .iter()
                .map(|i| i.name.as_str())
                .collect(),
            "mcp" => discover_data.mcp.iter().map(|i| i.name.as_str()).collect(),
            "permissions" => discover_data
                .permissions
                .iter()
                .map(|i| i.name.as_str())
                .collect(),
            _ => vec![],
        };

        let in_profile: Vec<String> = profile_data
            .get(t)
            .and_then(|v| v.as_object())
            .map(|obj| obj.keys().cloned().collect())
            .unwrap_or_default();

        let added_items: Vec<String> = on_disk
            .iter()
            .filter(|name| !in_profile.contains(&name.to_string()))
            .map(|s| s.to_string())
            .collect();
        let removed_items: Vec<String> = in_profile
            .iter()
            .filter(|name| !on_disk.contains(&name.as_str()))
            .cloned()
            .collect();

        match *t {
            "skills" => {
                added.skills = added_items;
                removed.skills = removed_items;
            }
            "hooks" => {
                added.hooks = added_items;
                removed.hooks = removed_items;
            }
            "mcp" => {
                added.mcp = added_items;
                removed.mcp = removed_items;
            }
            "permissions" => {
                added.permissions = added_items;
                removed.permissions = removed_items;
            }
            _ => {}
        }
    }

    ProfileDiff { added, removed }
}
