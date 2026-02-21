// config.rs - Config loading, merging, profile overrides

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;

/// Deployment config with Option fields for 5-layer merge.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DeployConfig {
    pub enabled: Option<bool>,
    pub scope: Option<String>,
    pub on_path: Option<bool>,
    pub dependencies: Option<Vec<String>>,
    pub permissions: Option<Permissions>,
    pub hooks_config: Option<Value>, // single object or array
    pub mcp: Option<Value>,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Permissions {
    #[serde(default)]
    pub allow: Vec<String>,
    #[serde(default)]
    pub deny: Vec<String>,
}

/// Resolved config with concrete values (no Options).
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct ResolvedConfig {
    pub enabled: bool,
    pub scope: String,
    pub on_path: bool,
    pub dependencies: Vec<String>,
    pub permissions: Option<Permissions>,
    pub hooks_config: Option<Value>,
    pub mcp: Option<Value>,
    pub description: Option<String>,
}

impl DeployConfig {
    /// Merge another config on top of self (other wins for present fields).
    pub fn merge(self, other: DeployConfig) -> DeployConfig {
        DeployConfig {
            enabled: other.enabled.or(self.enabled),
            scope: other.scope.or(self.scope),
            on_path: other.on_path.or(self.on_path),
            dependencies: other.dependencies.or(self.dependencies),
            permissions: other.permissions.or(self.permissions),
            hooks_config: other.hooks_config.or(self.hooks_config),
            mcp: other.mcp.or(self.mcp),
            description: other.description.or(self.description),
        }
    }

    /// Resolve to concrete values with defaults.
    pub fn resolve(self) -> ResolvedConfig {
        ResolvedConfig {
            enabled: self.enabled.unwrap_or(true),
            scope: self.scope.unwrap_or_else(|| "global".to_string()),
            on_path: self.on_path.unwrap_or(false),
            dependencies: self.dependencies.unwrap_or_default(),
            permissions: self.permissions,
            hooks_config: self.hooks_config,
            mcp: self.mcp,
            description: self.description,
        }
    }
}

/// Load a JSON file, returning empty object on any error.
pub fn load_json(path: &Path) -> Value {
    match std::fs::read_to_string(path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or(Value::Object(Default::default())),
        Err(_) => Value::Object(Default::default()),
    }
}

/// Load a JSON file as DeployConfig, returning default on any error.
pub fn load_deploy_config(path: &Path) -> DeployConfig {
    match std::fs::read_to_string(path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => DeployConfig::default(),
    }
}

/// Resolve deployment config for a tool/hook by merging 5 config layers.
///
/// Layers (lowest -> highest priority):
///   1. Hardcoded defaults
///   2. Repo-root deploy.json
///   3. Repo-root deploy.local.json
///   4. Item-level deploy.json
///   5. Item-level deploy.local.json
pub fn resolve_config(item_dir: &Path, repo_root: &Path) -> ResolvedConfig {
    let defaults = DeployConfig {
        enabled: Some(true),
        scope: Some("global".to_string()),
        on_path: Some(false),
        ..Default::default()
    };

    let layers = [
        load_deploy_config(&repo_root.join("deploy.json")),
        load_deploy_config(&repo_root.join("deploy.local.json")),
        load_deploy_config(&item_dir.join("deploy.json")),
        load_deploy_config(&item_dir.join("deploy.local.json")),
    ];

    let mut config = defaults;
    for layer in layers {
        config = config.merge(layer);
    }
    config.resolve()
}

/// Resolve config for a permission group file using 5-layer merge.
pub fn resolve_permission_config(base_file: &Path, repo_root: &Path) -> ResolvedConfig {
    let name = base_file.file_stem().unwrap().to_string_lossy();
    let local_file = base_file
        .parent()
        .unwrap()
        .join(format!("{}.local.json", name));

    let defaults = DeployConfig {
        enabled: Some(true),
        scope: Some("global".to_string()),
        on_path: Some(false),
        ..Default::default()
    };

    let layers = [
        load_deploy_config(&repo_root.join("deploy.json")),
        load_deploy_config(&repo_root.join("deploy.local.json")),
        load_deploy_config(base_file),
        load_deploy_config(&local_file),
    ];

    let mut config = defaults;
    for layer in layers {
        config = config.merge(layer);
    }
    config.resolve()
}

/// Apply profile overrides onto a resolved config.
///
/// When a profile is loaded it is AUTHORITATIVE:
/// - Items listed in the profile: merge their enabled/on_path values
/// - Items NOT in the profile: disabled (set enabled=False)
pub fn apply_profile_overrides(
    mut config: ResolvedConfig,
    profile_data: &Value,
    item_type: &str,
    item_name: &str,
) -> ResolvedConfig {
    if profile_data.is_null()
        || !profile_data.is_object()
        || profile_data.as_object().unwrap().is_empty()
    {
        return config;
    }

    let items = profile_data.get(item_type).and_then(|v| v.as_object());
    match items {
        None => {
            config.enabled = false;
            config
        }
        Some(items_map) => match items_map.get(item_name) {
            None => {
                config.enabled = false;
                config
            }
            Some(overrides) => {
                if let Some(enabled) = overrides.get("enabled").and_then(|v| v.as_bool()) {
                    config.enabled = enabled;
                }
                if let Some(on_path) = overrides.get("on_path").and_then(|v| v.as_bool()) {
                    config.on_path = on_path;
                }
                config
            }
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_merge_overrides() {
        let base = DeployConfig {
            enabled: Some(true),
            scope: Some("global".to_string()),
            ..Default::default()
        };
        let overlay = DeployConfig {
            scope: Some("project".to_string()),
            on_path: Some(true),
            ..Default::default()
        };
        let merged = base.merge(overlay);
        assert_eq!(merged.enabled, Some(true));
        assert_eq!(merged.scope, Some("project".to_string()));
        assert_eq!(merged.on_path, Some(true));
    }

    #[test]
    fn test_resolve_defaults() {
        let config = DeployConfig::default();
        let resolved = config.resolve();
        assert!(resolved.enabled);
        assert_eq!(resolved.scope, "global");
        assert!(!resolved.on_path);
    }

    #[test]
    fn test_load_json_missing_file() {
        let val = load_json(Path::new("/nonexistent/path.json"));
        assert!(val.is_object());
        assert!(val.as_object().unwrap().is_empty());
    }
}
