// settings.rs - Atomic read-modify-write for settings.json

use crate::config::load_json;
use crate::permissions::permission_sort_key;
use anyhow::Result;
use serde_json::{Map, Value};
use std::collections::BTreeSet;
use std::path::Path;

/// Atomically write JSON to a file via tempfile + rename.
fn atomic_write_json(path: &Path, data: &Value) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("tmp");
    let content = serde_json::to_string_pretty(data)? + "\n";
    std::fs::write(&tmp, &content)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Merge permission entries into settings.json using append-missing semantics.
pub fn update_settings_permissions(
    settings_path: &Path,
    allows: &[String],
    denies: &[String],
    dry_run: bool,
    skip_permissions: bool,
) -> Result<()> {
    if skip_permissions {
        println!("Skipped: permissions management (--skip-permissions)");
        return Ok(());
    }

    if dry_run {
        println!(
            "> Would update {} permissions ({} allow entries)",
            settings_path.display(),
            allows.len()
        );
        return Ok(());
    }

    let mut existing = load_json(settings_path);

    let existing_allows: BTreeSet<String> = existing
        .get("permissions")
        .and_then(|v| v.get("allow"))
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    let existing_denies: BTreeSet<String> = existing
        .get("permissions")
        .and_then(|v| v.get("deny"))
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    let mut merged_allows: Vec<String> = existing_allows
        .into_iter()
        .chain(allows.iter().cloned())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    merged_allows.sort_by_key(|a| permission_sort_key(a));

    let mut merged_denies: Vec<String> = existing_denies
        .into_iter()
        .chain(denies.iter().cloned())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    merged_denies.sort_by_key(|a| permission_sort_key(a));

    let obj = existing.as_object_mut().unwrap();
    if !obj.contains_key("permissions") {
        obj.insert("permissions".to_string(), Value::Object(Map::new()));
    }
    let perms = obj.get_mut("permissions").unwrap().as_object_mut().unwrap();
    perms.insert(
        "allow".to_string(),
        Value::Array(
            merged_allows
                .iter()
                .map(|s| Value::String(s.clone()))
                .collect(),
        ),
    );
    perms.insert(
        "deny".to_string(),
        Value::Array(
            merged_denies
                .iter()
                .map(|s| Value::String(s.clone()))
                .collect(),
        ),
    );

    let count = merged_allows.len();
    atomic_write_json(settings_path, &existing)?;
    println!(
        "Updated: {} permissions ({} allow entries)",
        settings_path.display(),
        count
    );

    Ok(())
}

/// Merge hook configs into settings.json using append-missing semantics.
pub fn update_settings_hooks(
    settings_path: &Path,
    hook_configs: &[(String, std::path::PathBuf)],
    hooks_base: &Path,
    dry_run: bool,
    skip_permissions: bool,
) -> Result<()> {
    if skip_permissions {
        println!("Skipped: hooks management (--skip-permissions)");
        return Ok(());
    }

    if hook_configs.is_empty() {
        return Ok(());
    }

    // Build new hooks from config files
    let mut new_hooks: Map<String, Value> = Map::new();

    for (hook_name, config_path) in hook_configs {
        let data = load_json(config_path);
        let hc_raw = match data.get("hooks_config") {
            Some(v) if !v.is_null() => v.clone(),
            _ => continue,
        };

        let hc_list: Vec<Value> = if hc_raw.is_array() {
            hc_raw.as_array().unwrap().clone()
        } else {
            vec![hc_raw]
        };

        for hc in &hc_list {
            let event = match hc.get("event").and_then(|v| v.as_str()) {
                Some(e) => e.to_string(),
                None => continue,
            };
            let command_script = match hc.get("command_script").and_then(|v| v.as_str()) {
                Some(s) => s.to_string(),
                None => continue,
            };
            let matcher = hc
                .get("matcher")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let async_flag = hc.get("async").and_then(|v| v.as_bool()).unwrap_or(false);
            let timeout_val = hc.get("timeout").and_then(|v| v.as_u64());

            let command_path = hooks_base.join(hook_name).join(&command_script);
            let command_path_str = command_path.to_string_lossy().to_string();

            let mut hook_entry = Map::new();
            hook_entry.insert("type".to_string(), Value::String("command".to_string()));
            hook_entry.insert("command".to_string(), Value::String(command_path_str));
            if async_flag {
                hook_entry.insert("async".to_string(), Value::Bool(true));
            }
            if let Some(t) = timeout_val {
                hook_entry.insert("timeout".to_string(), Value::Number(t.into()));
            }

            let mut matcher_group = Map::new();
            matcher_group.insert(
                "hooks".to_string(),
                Value::Array(vec![Value::Object(hook_entry)]),
            );
            if let Some(m) = matcher {
                matcher_group.insert("matcher".to_string(), Value::String(m));
            }

            let groups = new_hooks
                .entry(event)
                .or_insert_with(|| Value::Array(vec![]));
            groups
                .as_array_mut()
                .unwrap()
                .push(Value::Object(matcher_group));
        }
    }

    if dry_run {
        let event_count = new_hooks.len();
        println!(
            "> Would update {} hooks ({} events)",
            settings_path.display(),
            event_count
        );
        return Ok(());
    }

    let mut existing = load_json(settings_path);
    let obj = existing.as_object_mut().unwrap();

    if !obj.contains_key("hooks") {
        obj.insert("hooks".to_string(), Value::Object(Map::new()));
    }
    let existing_hooks = obj.get_mut("hooks").unwrap().as_object_mut().unwrap();

    for (event, groups) in &new_hooks {
        if !existing_hooks.contains_key(event) {
            existing_hooks.insert(event.clone(), Value::Array(vec![]));
        }
        let existing_groups = existing_hooks
            .get_mut(event)
            .unwrap()
            .as_array_mut()
            .unwrap();

        for group in groups.as_array().unwrap() {
            let new_matcher = group.get("matcher").and_then(|v| v.as_str());
            let already_present = existing_groups
                .iter()
                .any(|g| g.get("matcher").and_then(|v| v.as_str()) == new_matcher);
            if !already_present {
                existing_groups.push(group.clone());
            }
        }
    }

    let event_count = existing_hooks.len();
    atomic_write_json(settings_path, &existing)?;
    println!(
        "Updated: {} hooks ({} events)",
        settings_path.display(),
        event_count
    );

    Ok(())
}

/// Merge MCP server definitions into settings using append-missing semantics.
pub fn update_settings_mcp(
    settings_path: &Path,
    mcp_configs: &[(String, Value)],
    project_path: Option<&Path>,
    dry_run: bool,
    skip_permissions: bool,
) -> Result<()> {
    if skip_permissions {
        println!("Skipped: MCP server management (--skip-permissions)");
        return Ok(());
    }

    if mcp_configs.is_empty() {
        return Ok(());
    }

    let target_path = if let Some(pp) = project_path {
        pp.join(".mcp.json")
    } else {
        settings_path.to_path_buf()
    };

    if dry_run {
        let names: Vec<&str> = mcp_configs.iter().map(|(n, _)| n.as_str()).collect();
        println!(
            "> Would update {} mcpServers ({})",
            target_path.display(),
            names.join(", ")
        );
        return Ok(());
    }

    let mut existing = load_json(&target_path);
    let obj = existing.as_object_mut().unwrap();

    if !obj.contains_key("mcpServers") {
        obj.insert("mcpServers".to_string(), Value::Object(Map::new()));
    }
    let servers = obj.get_mut("mcpServers").unwrap().as_object_mut().unwrap();

    for (name, server_def) in mcp_configs {
        if !servers.contains_key(name) {
            servers.insert(name.clone(), server_def.clone());
        }
    }

    let count = servers.len();
    atomic_write_json(&target_path, &existing)?;
    println!(
        "Updated: {} mcpServers ({} servers)",
        target_path.display(),
        count
    );

    Ok(())
}

/// Remove named MCP servers from settings.
pub fn remove_settings_mcp(
    settings_path: &Path,
    server_names: &[String],
    dry_run: bool,
) -> Result<()> {
    if server_names.is_empty() {
        return Ok(());
    }

    if dry_run {
        let names = server_names.join(", ");
        println!(
            "> Would remove from {} mcpServers: {}",
            settings_path.display(),
            names
        );
        return Ok(());
    }

    let mut existing = load_json(settings_path);
    let servers = match existing
        .as_object_mut()
        .and_then(|obj| obj.get_mut("mcpServers"))
        .and_then(|v| v.as_object_mut())
    {
        Some(s) => s,
        None => {
            println!(
                "No matching MCP servers found in {}",
                settings_path.display()
            );
            return Ok(());
        }
    };

    let mut removed = Vec::new();
    for name in server_names {
        if servers.remove(name).is_some() {
            removed.push(name.as_str());
        }
    }

    if removed.is_empty() {
        println!(
            "No matching MCP servers found in {}",
            settings_path.display()
        );
    } else {
        atomic_write_json(settings_path, &existing)?;
        println!(
            "Removed from {} mcpServers: {}",
            settings_path.display(),
            removed.join(", ")
        );
    }

    Ok(())
}
