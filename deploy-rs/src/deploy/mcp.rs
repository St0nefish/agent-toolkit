// deploy/mcp.rs - MCP server deployment logic

use crate::config::{apply_profile_overrides, resolve_config};
use anyhow::Result;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Context for deploying an MCP server.
pub struct McpDeployCtx<'a> {
    pub repo_root: &'a Path,
    pub profile_data: &'a Value,
    pub include: &'a [String],
    pub exclude: &'a [String],
    pub dry_run: bool,
    pub deployed_configs: &'a mut Vec<PathBuf>,
    pub mcp_configs: &'a mut Vec<(String, Value)>,
    pub profile_new_items: &'a mut Vec<String>,
}

/// Deploy a single MCP server directory. Returns true if deployed.
pub fn deploy_mcp(mcp_dir: &Path, ctx: &mut McpDeployCtx) -> Result<bool> {
    let mcp_name = mcp_dir.file_name().unwrap().to_string_lossy().to_string();

    // Pre-deploy checks
    if is_filtered_out(&mcp_name, ctx.include, ctx.exclude) {
        println!("  Skipped: {} (filtered out)", mcp_name);
        return Ok(false);
    }

    let config = resolve_config(mcp_dir, ctx.repo_root);
    let config = apply_profile_overrides(config, ctx.profile_data, "mcp", &mcp_name);

    // Track new items for profile drift
    if !ctx.profile_data.is_null()
        && ctx.profile_data.is_object()
        && !ctx.profile_data.as_object().unwrap().is_empty()
    {
        let in_profile = ctx
            .profile_data
            .get("mcp")
            .and_then(|v| v.as_object())
            .map(|m| m.contains_key(&mcp_name))
            .unwrap_or(false);
        if !in_profile {
            ctx.profile_new_items.push(format!("{} (mcp)", mcp_name));
        }
    }

    if !config.enabled {
        println!("  Skipped: {} (disabled by config)", mcp_name);
        return Ok(false);
    }

    // Validate: config must have an "mcp" key with "command" or "url"
    let mcp_def = match &config.mcp {
        Some(v) if v.is_object() => {
            let obj = v.as_object().unwrap();
            if !obj.contains_key("command") && !obj.contains_key("url") {
                println!(
                    "  Skipped: {} ('mcp' key must have 'command' or 'url')",
                    mcp_name
                );
                return Ok(false);
            }
            v.clone()
        }
        _ => {
            println!(
                "  Skipped: {} ('mcp' key must have 'command' or 'url')",
                mcp_name
            );
            return Ok(false);
        }
    };

    // Run setup.sh if present
    let setup_script = mcp_dir.join("setup.sh");
    if setup_script.exists() && is_executable(&setup_script) {
        if ctx.dry_run {
            println!("  > Would run: {}", setup_script.display());
        } else {
            println!("  Running: {}", setup_script.display());
            let result = Command::new(setup_script.to_str().unwrap()).output()?;

            let stdout = String::from_utf8_lossy(&result.stdout);
            if !stdout.trim().is_empty() {
                for line in stdout.trim().lines() {
                    println!("    {}", line);
                }
            }

            if !result.status.success() {
                let code = result.status.code().unwrap_or(-1);
                println!("  Warning: {} setup.sh failed (exit {})", mcp_name, code);
                let stderr = String::from_utf8_lossy(&result.stderr);
                if !stderr.trim().is_empty() {
                    for line in stderr.trim().lines() {
                        println!("    {}", line);
                    }
                }
                return Ok(false);
            }
        }
    }

    // Collect config for MCP settings registration
    ctx.mcp_configs.push((mcp_name.clone(), mcp_def));

    // Collect deploy.json paths for permission collection
    for cfg_name in &["deploy.json", "deploy.local.json"] {
        let p = mcp_dir.join(cfg_name);
        if p.exists() {
            ctx.deployed_configs.push(p);
        }
    }

    println!("  Deployed: {}", mcp_name);
    Ok(true)
}

/// Run setup.sh --teardown for an MCP server. Returns true on success.
pub fn teardown_mcp(mcp_dir: &Path, dry_run: bool) -> bool {
    let mcp_name = mcp_dir.file_name().unwrap().to_string_lossy().to_string();

    let setup_script = mcp_dir.join("setup.sh");
    if !setup_script.exists() || !is_executable(&setup_script) {
        println!("  Skipped: {} (no setup.sh)", mcp_name);
        return true;
    }

    if dry_run {
        println!("  > Would run: {} --teardown", setup_script.display());
        return true;
    }

    println!("  Running: {} --teardown", setup_script.display());
    match Command::new(setup_script.to_str().unwrap())
        .arg("--teardown")
        .output()
    {
        Ok(result) => {
            let stdout = String::from_utf8_lossy(&result.stdout);
            if !stdout.trim().is_empty() {
                for line in stdout.trim().lines() {
                    println!("    {}", line);
                }
            }
            if !result.status.success() {
                let code = result.status.code().unwrap_or(-1);
                println!("  Warning: {} teardown failed (exit {})", mcp_name, code);
                let stderr = String::from_utf8_lossy(&result.stderr);
                if !stderr.trim().is_empty() {
                    for line in stderr.trim().lines() {
                        println!("    {}", line);
                    }
                }
                return false;
            }
            true
        }
        Err(e) => {
            println!("  Warning: {} teardown failed: {}", mcp_name, e);
            false
        }
    }
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(_path: &Path) -> bool {
    true
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
