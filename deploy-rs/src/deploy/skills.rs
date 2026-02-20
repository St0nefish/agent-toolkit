// deploy/skills.rs - Skill deployment logic

use crate::config::{apply_profile_overrides, resolve_config};
use crate::linker::{ensure_link, is_globally_deployed};
use anyhow::Result;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

/// Context for deploying a skill.
pub struct SkillDeployCtx<'a> {
    pub repo_root: &'a Path,
    pub profile_data: &'a serde_json::Value,
    pub include: &'a [String],
    pub exclude: &'a [String],
    pub project_path: Option<&'a Path>,
    pub cli_on_path: bool,
    pub global_skills_base: &'a Path,
    pub tools_base: &'a Path,
    pub dry_run: bool,
    pub deployed_configs: &'a mut Vec<PathBuf>,
    pub profile_new_items: &'a mut Vec<String>,
    /// Per-script PATH control from TUI. Maps skill_name -> set of script names.
    /// When empty, falls back to all-or-nothing on_path behavior.
    pub on_path_scripts: &'a HashMap<String, HashSet<String>>,
}

/// Deploy a single skill directory. Returns true if deployed.
pub fn deploy_skill(skill_dir: &Path, ctx: &mut SkillDeployCtx) -> Result<bool> {
    let skill_name = skill_dir.file_name().unwrap().to_string_lossy().to_string();

    // Pre-deploy checks
    if is_filtered_out(&skill_name, ctx.include, ctx.exclude) {
        println!("  Skipped: {} (filtered out)", skill_name);
        return Ok(false);
    }

    let config = resolve_config(skill_dir, ctx.repo_root);
    let config = apply_profile_overrides(config, ctx.profile_data, "skills", &skill_name);

    // Track new items for profile drift
    if !ctx.profile_data.is_null()
        && ctx.profile_data.is_object()
        && !ctx.profile_data.as_object().unwrap().is_empty()
    {
        let in_profile = ctx
            .profile_data
            .get("skills")
            .and_then(|v| v.as_object())
            .map(|m| m.contains_key(&skill_name))
            .unwrap_or(false);
        if !in_profile {
            ctx.profile_new_items
                .push(format!("{} (skills)", skill_name));
        }
    }

    if !config.enabled {
        println!("  Skipped: {} (disabled by config)", skill_name);
        return Ok(false);
    }

    // Scope resolution
    let effective_scope = if ctx.project_path.is_some() {
        "project"
    } else if config.scope == "project" {
        println!(
            "  Skipped: {} (scope=project, no --project flag given)",
            skill_name
        );
        return Ok(false);
    } else {
        "global"
    };

    let effective_on_path = ctx.cli_on_path || config.on_path;

    let skills_base = if effective_scope == "project" {
        ctx.project_path.unwrap().join(".claude").join("skills")
    } else {
        ctx.global_skills_base.to_path_buf()
    };

    if ctx.dry_run {
        println!("  > mkdir -p {}", skills_base.display());
    } else {
        std::fs::create_dir_all(&skills_base)?;
    }

    // Link tool directory
    ensure_link(
        &ctx.tools_base.join(&skill_name),
        skill_dir,
        &format!("~/.claude/tools/{}", skill_name),
        ctx.dry_run,
        true,
    )?;

    // Collect and deploy skills
    let skills = collect_skills(skill_dir, &skill_name);

    for (deploy_name, md_path) in &skills {
        if effective_scope == "project" && is_globally_deployed(deploy_name, ctx.global_skills_base)
        {
            println!("  Skipped: {} (already deployed globally)", deploy_name);
            continue;
        }

        let subdir = skills_base.join(deploy_name);
        if ctx.dry_run {
            println!("  > mkdir -p {}", subdir.display());
        } else {
            std::fs::create_dir_all(&subdir)?;
        }

        ensure_link(
            &subdir.join("SKILL.md"),
            md_path,
            &format!("{}", subdir.join("SKILL.md").display()),
            ctx.dry_run,
            false,
        )?;
    }

    // Clean up stale old-style symlinks
    cleanup_stale_skill_links(&skills_base, &skill_name, ctx.dry_run);

    // On-path deployment: per-script (TUI) or all-or-nothing (CLI)
    let tui_script_set = ctx.on_path_scripts.get(&skill_name);
    let should_do_path = tui_script_set.is_some() || effective_on_path;

    if should_do_path {
        let bin_dir = skill_dir.join("bin");
        if bin_dir.is_dir() {
            let local_bin = dirs::home_dir().unwrap().join(".local").join("bin");
            if ctx.dry_run {
                println!("  > mkdir -p {}", local_bin.display());
            } else {
                std::fs::create_dir_all(&local_bin)?;
            }
            if let Ok(entries) = std::fs::read_dir(&bin_dir) {
                let mut scripts: Vec<_> = entries.filter_map(|e| e.ok()).collect();
                scripts.sort_by_key(|e| e.file_name());
                for entry in scripts {
                    let path = entry.path();
                    if !path.is_file() {
                        continue;
                    }
                    let name = entry.file_name();
                    let name_str = name.to_string_lossy().to_string();
                    // If TUI provided a script set, only symlink listed scripts
                    if let Some(script_set) = tui_script_set {
                        if !script_set.contains(&name_str) {
                            continue;
                        }
                    }
                    ensure_link(
                        &local_bin.join(&name),
                        &path,
                        &format!("~/.local/bin/{}", name_str),
                        ctx.dry_run,
                        false,
                    )?;
                }
            }
        }
    }

    // Collect deploy configs for permission management
    collect_deploy_configs(skill_dir, ctx.deployed_configs);

    // Handle dependencies
    for dep in &config.dependencies {
        if dep.is_empty() {
            continue;
        }
        let dep_dir = ctx.repo_root.join("skills").join(dep);
        if !dep_dir.is_dir() {
            println!(
                "  Warning: dependency '{}' not found (required by {})",
                dep, skill_name
            );
            continue;
        }
        ensure_link(
            &ctx.tools_base.join(dep),
            &dep_dir,
            &format!("~/.claude/tools/{} (dependency of {})", dep, skill_name),
            ctx.dry_run,
            true,
        )?;
        collect_deploy_configs(&dep_dir, ctx.deployed_configs);
    }

    println!("  Deployed: {}", skill_name);
    Ok(true)
}

/// Collect deployable skills from a skill directory.
///
/// Supports two source layouts:
///   Legacy (loose .md files):
///     skills/session/start.md -> ("session-start", .../start.md)
///     skills/catchup/catchup.md -> ("catchup", .../catchup.md)
///   Modern (subdirectories with SKILL.md):
///     skills/session/start/SKILL.md -> ("session-start", .../start/SKILL.md)
fn collect_skills(skill_dir: &Path, skill_name: &str) -> Vec<(String, PathBuf)> {
    let mut modern_skills = Vec::new();

    // Modern pattern: subdirectories containing SKILL.md
    if let Ok(entries) = std::fs::read_dir(skill_dir) {
        let mut subdirs: Vec<_> = entries
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir() && e.file_name() != "bin")
            .collect();
        subdirs.sort_by_key(|e| e.file_name());

        for subdir in subdirs {
            let skill_md = subdir.path().join("SKILL.md");
            if skill_md.is_file() {
                let subdir_name = subdir.file_name().to_string_lossy().to_string();
                modern_skills.push((format!("{}-{}", skill_name, subdir_name), skill_md));
            }
        }
    }

    // Legacy pattern: loose .md files (excluding README.md)
    let mut md_files: Vec<PathBuf> = std::fs::read_dir(skill_dir)
        .ok()
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| {
                    p.extension().map(|e| e == "md").unwrap_or(false)
                        && p.file_name().map(|n| n != "README.md").unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default();
    md_files.sort();

    // Both patterns present - only use modern
    if !modern_skills.is_empty() && !md_files.is_empty() {
        return modern_skills;
    }

    if !modern_skills.is_empty() {
        return modern_skills;
    }

    if md_files.is_empty() {
        return vec![];
    }

    if md_files.len() == 1 {
        vec![(skill_name.to_string(), md_files[0].clone())]
    } else {
        md_files
            .iter()
            .map(|md| {
                let stem = md.file_stem().unwrap().to_string_lossy().to_string();
                (format!("{}-{}", skill_name, stem), md.clone())
            })
            .collect()
    }
}

/// Remove old-style skill layouts that the new SKILL.md format replaces.
fn cleanup_stale_skill_links(skills_base: &Path, skill_name: &str, dry_run: bool) {
    // Flat .md symlink
    let flat = skills_base.join(format!("{}.md", skill_name));
    if flat.is_symlink() {
        if dry_run {
            println!("  > rm {}", flat.display());
        } else {
            let _ = std::fs::remove_file(&flat);
        }
        println!("  Cleaned: stale flat symlink {}", flat.display());
    }

    // Colon-namespaced subdirectory
    let old_subdir = skills_base.join(skill_name);
    if old_subdir.is_dir() && !old_subdir.is_symlink() {
        if let Ok(entries) = std::fs::read_dir(&old_subdir) {
            let entries: Vec<_> = entries.filter_map(|e| e.ok()).collect();
            for entry in &entries {
                let p = entry.path();
                if p.is_symlink() && p.file_name().map(|n| n != "SKILL.md").unwrap_or(false) {
                    if dry_run {
                        println!("  > rm {}", p.display());
                    } else {
                        let _ = std::fs::remove_file(&p);
                    }
                    println!("  Cleaned: stale symlink {}", p.display());
                }
            }
            // Remove if empty
            if std::fs::read_dir(&old_subdir)
                .map(|mut d| d.next().is_none())
                .unwrap_or(false)
            {
                if dry_run {
                    println!("  > rmdir {}", old_subdir.display());
                } else {
                    let _ = std::fs::remove_dir(&old_subdir);
                }
                println!("  Cleaned: stale directory {}", old_subdir.display());
            }
        }
    }

    // Directory symlink pointing at source (very old layout)
    if old_subdir.is_symlink() && old_subdir.is_dir() {
        if let Ok(target) = std::fs::read_link(&old_subdir) {
            let target_str = target.to_string_lossy();
            if target_str.contains("/skills/") {
                if dry_run {
                    println!("  > rm {}", old_subdir.display());
                } else {
                    let _ = std::fs::remove_file(&old_subdir);
                }
                println!(
                    "  Cleaned: stale directory symlink {}",
                    old_subdir.display()
                );
            }
        }
    }
}

/// Append deploy.json and deploy.local.json from a directory to the config list.
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
