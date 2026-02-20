// deploy/hooks.rs - Hook deployment logic

use crate::config::{apply_profile_overrides, load_json, resolve_config};
use crate::linker::ensure_link;
use anyhow::Result;
use std::path::{Path, PathBuf};

/// Context for deploying a hook.
pub struct HookDeployCtx<'a> {
    pub repo_root: &'a Path,
    pub profile_data: &'a serde_json::Value,
    pub include: &'a [String],
    pub exclude: &'a [String],
    pub hooks_base: &'a Path,
    pub dry_run: bool,
    pub deployed_configs: &'a mut Vec<PathBuf>,
    pub hook_configs: &'a mut Vec<(String, PathBuf)>,
    pub profile_new_items: &'a mut Vec<String>,
}

/// Deploy a single hook directory. Returns true if deployed.
pub fn deploy_hook(hook_dir: &Path, ctx: &mut HookDeployCtx) -> Result<bool> {
    let hook_name = hook_dir.file_name().unwrap().to_string_lossy().to_string();

    // Pre-deploy checks
    if is_filtered_out(&hook_name, ctx.include, ctx.exclude) {
        println!("  Skipped: hook {} (filtered out)", hook_name);
        return Ok(false);
    }

    let config = resolve_config(hook_dir, ctx.repo_root);
    let config = apply_profile_overrides(config, ctx.profile_data, "hooks", &hook_name);

    // Track new items for profile drift
    if !ctx.profile_data.is_null()
        && ctx.profile_data.is_object()
        && !ctx.profile_data.as_object().unwrap().is_empty()
    {
        let in_profile = ctx
            .profile_data
            .get("hooks")
            .and_then(|v| v.as_object())
            .map(|m| m.contains_key(&hook_name))
            .unwrap_or(false);
        if !in_profile {
            ctx.profile_new_items.push(format!("{} (hooks)", hook_name));
        }
    }

    if !config.enabled {
        println!("  Skipped: hook {} (disabled by config)", hook_name);
        return Ok(false);
    }

    ensure_link(
        &ctx.hooks_base.join(&hook_name),
        hook_dir,
        &format!("~/.claude/hooks/{}", hook_name),
        ctx.dry_run,
        true,
    )?;

    // Collect deploy configs
    collect_deploy_configs(hook_dir, ctx.deployed_configs);

    // Check for hooks_config in deploy.json
    let hook_deploy_json = hook_dir.join("deploy.json");
    if hook_deploy_json.exists() {
        let data = load_json(&hook_deploy_json);
        if data.get("hooks_config").is_some() {
            ctx.hook_configs.push((hook_name.clone(), hook_deploy_json));
        }
    }

    println!("  Deployed: hook {}", hook_name);
    Ok(true)
}

fn collect_deploy_configs(item_dir: &Path, deployed_configs: &mut Vec<PathBuf>) {
    for cfg_name in &["deploy.json", "deploy.local.json"] {
        let p = item_dir.join(cfg_name);
        if p.exists() {
            deployed_configs.push(p);
        }
    }
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
