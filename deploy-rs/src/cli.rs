// cli.rs - CLI argument parsing and main orchestration

use crate::deploy::hooks::{deploy_hook, HookDeployCtx};
use crate::deploy::mcp::{deploy_mcp, teardown_mcp, McpDeployCtx};
use crate::deploy::permission_groups::deploy_permission_groups;
use crate::deploy::skills::{deploy_skill, SkillDeployCtx};
use crate::discovery::{discover_items, profile_diff};
use crate::linker::cleanup_broken_symlinks;
use crate::permissions::collect_permissions;
use crate::settings::{
    remove_settings_mcp, update_settings_hooks, update_settings_mcp, update_settings_permissions,
};
use anyhow::Result;
use clap::Parser;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

#[derive(Parser, Debug)]
#[command(
    name = "deploy",
    about = "Deploy Claude Code skills, tool scripts, hooks, MCP servers, and permission groups."
)]
pub struct Cli {
    /// Deploy globally (default, explicit no-op)
    #[arg(long = "global")]
    pub global_flag: bool,

    /// Deploy skills to PATH/.claude/skills/ instead of globally
    #[arg(long)]
    pub project: Option<String>,

    /// Also symlink scripts to ~/.local/bin/
    #[arg(long = "on-path")]
    pub on_path: bool,

    /// Load a deployment profile
    #[arg(long)]
    pub profile: Option<String>,

    /// Only deploy these tools (comma or space-separated)
    #[arg(long, value_delimiter = ',', num_args = 1..)]
    pub include: Vec<String>,

    /// Deploy all tools EXCEPT these (comma or space-separated)
    #[arg(long, value_delimiter = ',', num_args = 1..)]
    pub exclude: Vec<String>,

    /// Teardown named MCP servers and remove config
    #[arg(long = "teardown-mcp", value_delimiter = ',', num_args = 1..)]
    pub teardown_mcp: Vec<String>,

    /// Output JSON of all items with merged config and exit
    #[arg(long)]
    pub discover: bool,

    /// Show what would be done without making any changes
    #[arg(long = "dry-run")]
    pub dry_run: bool,

    /// Skip settings.json permission management
    #[arg(long = "skip-permissions")]
    pub skip_permissions: bool,

    /// Force interactive TUI mode
    #[arg(long)]
    pub interactive: bool,
}

/// Context for a single deploy pass. Used by both CLI and TUI.
pub struct DeployContext {
    pub repo_root: PathBuf,
    pub claude_config_dir: PathBuf,
    pub project_path: Option<PathBuf>,
    pub on_path: bool,
    pub dry_run: bool,
    pub skip_permissions: bool,
    pub include: Vec<String>,
    pub exclude: Vec<String>,
    pub profile_data: Value,
    /// When true, suppress stdout (TUI captures output via output_lines instead).
    #[allow(dead_code)]
    pub quiet: bool,
    /// Per-script PATH control from TUI. Maps skill_name -> set of script names to symlink.
    /// When empty (CLI mode), falls back to all-or-nothing on_path behavior.
    pub on_path_scripts: HashMap<String, HashSet<String>>,
}

/// Summary of a deploy pass.
#[allow(dead_code)]
pub struct DeploySummary {
    pub skills_deployed: Vec<String>,
    pub hooks_deployed: Vec<String>,
    pub mcp_registered: Vec<String>,
    pub permissions_applied: Vec<String>,
    pub output_lines: Vec<String>,
}

/// Normalize include/exclude lists (flatten commas).
fn normalize_list(items: &[String]) -> Vec<String> {
    items
        .iter()
        .flat_map(|item| item.split(',').map(|s| s.trim().to_string()))
        .filter(|s| !s.is_empty())
        .collect()
}

/// Load a deployment profile, returning (path_str, data).
fn load_profile(profile_arg: &str, _repo_root: &Path) -> (String, Value) {
    if profile_arg.is_empty() {
        return (String::new(), Value::Object(Default::default()));
    }

    let profile_file = Path::new(profile_arg);
    if !profile_file.exists() {
        return (String::new(), Value::Null); // caller handles error
    }

    let data = crate::config::load_json(profile_file);
    (profile_arg.to_string(), data)
}

/// Check for stale items in profile (in profile but not seen on disk).
fn check_profile_drift(
    seen_skills: &[String],
    seen_hooks: &[String],
    profile_data: &Value,
    seen_mcp: &[String],
    seen_permissions: &[String],
) -> Vec<String> {
    if !profile_data.is_object() || profile_data.as_object().unwrap().is_empty() {
        return vec![];
    }

    let mut stale = Vec::new();

    let categories = [
        ("skills", seen_skills),
        ("hooks", seen_hooks),
        ("mcp", seen_mcp),
        ("permissions", seen_permissions),
    ];

    for (cat, seen) in &categories {
        if let Some(profile_items) = profile_data.get(*cat).and_then(|v| v.as_object()) {
            let mut keys: Vec<&String> = profile_items.keys().collect();
            keys.sort();
            for key in keys {
                if !seen.iter().any(|s| s == key) {
                    stale.push(format!("{} ({})", key, cat));
                }
            }
        }
    }

    stale
}

/// Execute a single deploy pass. Reused by both headless CLI and TUI.
pub fn execute_deploy(ctx: &DeployContext) -> Result<DeploySummary> {
    let repo_root = &ctx.repo_root;
    let claude_config_dir = &ctx.claude_config_dir;
    let profile_data_ref = &ctx.profile_data;

    let global_skills_base = claude_config_dir.join("skills");
    let tools_base = claude_config_dir.join("tools");
    let hooks_base = claude_config_dir.join("hooks");

    let mut output_lines = Vec::new();
    let mut skills_deployed = Vec::new();
    let mut hooks_deployed = Vec::new();
    let mut mcp_registered = Vec::new();
    let mut permissions_applied = Vec::new();

    // --- Dry-run banner ---
    if ctx.dry_run {
        let line = "=== DRY RUN (no changes will be made) ===";
        println!("{}", line);
        output_lines.push(line.to_string());
        println!();
        output_lines.push(String::new());
    }

    // --- Create base directories ---
    if ctx.dry_run {
        println!("> mkdir -p {}", global_skills_base.display());
        println!("> mkdir -p {}", tools_base.display());
    } else {
        std::fs::create_dir_all(&global_skills_base)?;
        std::fs::create_dir_all(&tools_base)?;
    }

    // --- Clean broken symlinks ---
    cleanup_broken_symlinks(&tools_base, "dir", ctx.dry_run);
    cleanup_broken_symlinks(&global_skills_base, "", ctx.dry_run);

    if let Some(ref pp) = ctx.project_path {
        let project_skills = pp.join(".claude").join("skills");
        if ctx.dry_run {
            println!("> mkdir -p {}", project_skills.display());
        } else {
            std::fs::create_dir_all(&project_skills)?;
        }
        cleanup_broken_symlinks(&project_skills, "", ctx.dry_run);
    }

    if hooks_base.is_dir() {
        cleanup_broken_symlinks(&hooks_base, "dir", ctx.dry_run);
    }

    // --- Collect repo-root config files ---
    let mut deployed_configs: Vec<PathBuf> = Vec::new();
    for cfg_name in &["deploy.json", "deploy.local.json"] {
        let p = repo_root.join(cfg_name);
        if p.exists() {
            deployed_configs.push(p);
        }
    }

    // --- Deploy skills ---
    let skills_dir = repo_root.join("skills");
    let mut seen_skills = Vec::new();
    let mut profile_new_items = Vec::new();
    let mut hook_configs: Vec<(String, PathBuf)> = Vec::new();

    if !skills_dir.is_dir() {
        let line = "No skills/ directory found.";
        println!("{}", line);
        output_lines.push(line.to_string());
        update_settings_permissions(
            &claude_config_dir.join("settings.json"),
            &[],
            &[],
            ctx.dry_run,
            ctx.skip_permissions,
        )?;
        return Ok(DeploySummary {
            skills_deployed,
            hooks_deployed,
            mcp_registered,
            permissions_applied,
            output_lines,
        });
    }

    let line = "=== Skills ===";
    println!("{}", line);
    output_lines.push(line.to_string());

    let mut skill_entries: Vec<_> = std::fs::read_dir(&skills_dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .collect();
    skill_entries.sort_by_key(|e| e.file_name());

    for entry in &skill_entries {
        let skill_dir = entry.path();
        let skill_name = entry.file_name().to_string_lossy().to_string();
        seen_skills.push(skill_name.clone());

        let mut skill_ctx = SkillDeployCtx {
            repo_root,
            profile_data: profile_data_ref,
            include: &ctx.include,
            exclude: &ctx.exclude,
            project_path: ctx.project_path.as_deref(),
            cli_on_path: ctx.on_path,
            global_skills_base: &global_skills_base,
            tools_base: &tools_base,
            dry_run: ctx.dry_run,
            deployed_configs: &mut deployed_configs,
            profile_new_items: &mut profile_new_items,
            on_path_scripts: &ctx.on_path_scripts,
        };

        deploy_skill(&skill_dir, &mut skill_ctx)?;
        skills_deployed.push(skill_name);
    }

    // --- Deploy hooks ---
    let hooks_dir = repo_root.join("hooks");
    let mut seen_hooks = Vec::new();

    if hooks_dir.is_dir() {
        if ctx.dry_run {
            println!("> mkdir -p {}", hooks_base.display());
        } else {
            std::fs::create_dir_all(&hooks_base)?;
        }

        println!();
        let line = "=== Hooks ===";
        println!("{}", line);
        output_lines.push(line.to_string());

        let mut hook_entries: Vec<_> = std::fs::read_dir(&hooks_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir())
            .collect();
        hook_entries.sort_by_key(|e| e.file_name());

        for entry in &hook_entries {
            let hook_dir = entry.path();
            let hook_name = entry.file_name().to_string_lossy().to_string();
            seen_hooks.push(hook_name.clone());

            let mut hook_ctx = HookDeployCtx {
                repo_root,
                profile_data: profile_data_ref,
                include: &ctx.include,
                exclude: &ctx.exclude,
                hooks_base: &hooks_base,
                dry_run: ctx.dry_run,
                deployed_configs: &mut deployed_configs,
                hook_configs: &mut hook_configs,
                profile_new_items: &mut profile_new_items,
            };

            deploy_hook(&hook_dir, &mut hook_ctx)?;
            hooks_deployed.push(hook_name);
        }
    }

    // --- Deploy MCP servers ---
    let mcp_dir_root = repo_root.join("mcp");
    let mut seen_mcp = Vec::new();
    let mut mcp_configs: Vec<(String, Value)> = Vec::new();

    if mcp_dir_root.is_dir() {
        println!();
        let line = "=== MCP ===";
        println!("{}", line);
        output_lines.push(line.to_string());

        let mut mcp_entries: Vec<_> = std::fs::read_dir(&mcp_dir_root)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir())
            .collect();
        mcp_entries.sort_by_key(|e| e.file_name());

        for entry in &mcp_entries {
            let mcp_dir = entry.path();
            let mcp_name = entry.file_name().to_string_lossy().to_string();
            seen_mcp.push(mcp_name.clone());

            let mut mcp_ctx = McpDeployCtx {
                repo_root,
                profile_data: profile_data_ref,
                include: &ctx.include,
                exclude: &ctx.exclude,
                dry_run: ctx.dry_run,
                deployed_configs: &mut deployed_configs,
                mcp_configs: &mut mcp_configs,
                profile_new_items: &mut profile_new_items,
            };

            deploy_mcp(&mcp_dir, &mut mcp_ctx)?;
            mcp_registered.push(mcp_name);
        }
    }

    // --- Deploy permission groups ---
    let permissions_dir = repo_root.join("permissions");
    let mut seen_permissions = Vec::new();

    if permissions_dir.is_dir() {
        println!();
        let line = "=== Permissions ===";
        println!("{}", line);
        output_lines.push(line.to_string());

        seen_permissions = deploy_permission_groups(
            &permissions_dir,
            repo_root,
            profile_data_ref,
            &mut profile_new_items,
            &ctx.include,
            &ctx.exclude,
            ctx.dry_run,
            &mut deployed_configs,
        );
        permissions_applied = seen_permissions.clone();
    }

    // --- Manage settings.json permissions ---
    println!();

    // Deduplicate config paths
    let mut seen_paths = HashSet::new();
    let unique_configs: Vec<&Path> = deployed_configs
        .iter()
        .filter(|p| seen_paths.insert(p.to_string_lossy().to_string()))
        .map(|p| p.as_path())
        .collect();

    let (allows, denies) = collect_permissions(&unique_configs);

    let settings_file = if let Some(ref pp) = ctx.project_path {
        pp.join(".claude").join("settings.json")
    } else {
        claude_config_dir.join("settings.json")
    };

    update_settings_permissions(
        &settings_file,
        &allows,
        &denies,
        ctx.dry_run,
        ctx.skip_permissions,
    )?;

    // --- Manage settings.json hooks (always global) ---
    let hooks_settings_file = claude_config_dir.join("settings.json");
    update_settings_hooks(
        &hooks_settings_file,
        &hook_configs,
        &hooks_base,
        ctx.dry_run,
        ctx.skip_permissions,
    )?;

    // --- Manage MCP server config ---
    let mcp_settings_file = claude_config_dir.join("settings.json");
    update_settings_mcp(
        &mcp_settings_file,
        &mcp_configs,
        ctx.project_path.as_deref(),
        ctx.dry_run,
        ctx.skip_permissions,
    )?;

    // --- Summary footer ---
    println!();
    if let Some(ref pp) = ctx.project_path {
        let line = format!(
            "Deployed to: {}/.claude/skills (project skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)",
            pp.display()
        );
        println!("{}", line);
        output_lines.push(line);
    } else {
        let line =
            "Deployed to: ~/.claude/skills (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)".to_string();
        println!("{}", line);
        output_lines.push(line);
    }

    if !mcp_configs.is_empty() {
        let names: Vec<&str> = mcp_configs.iter().map(|(n, _)| n.as_str()).collect();
        let line = format!("MCP servers registered: {}", names.join(", "));
        println!("{}", line);
        output_lines.push(line);
    }

    if ctx.on_path {
        let line = "Scripts also linked to: ~/.local/bin (via --on-path flag)";
        println!("{}", line);
        output_lines.push(line.to_string());
    }

    // --- Check profile drift ---
    if !profile_data_ref
        .as_object()
        .unwrap_or(&Default::default())
        .is_empty()
    {
        let stale_items = check_profile_drift(
            &seen_skills,
            &seen_hooks,
            profile_data_ref,
            &seen_mcp,
            &seen_permissions,
        );

        if !profile_new_items.is_empty() || !stale_items.is_empty() {
            println!();
            println!("WARNING: Profile drift detected:");
            if !profile_new_items.is_empty() {
                println!("  New items (not in profile, skipped):");
                for item in &profile_new_items {
                    println!("    - {}", item);
                }
            }
            if !stale_items.is_empty() {
                println!("  Stale items (in profile, no longer on disk):");
                for item in &stale_items {
                    println!("    - {}", item);
                }
            }
            println!("  Run the deploy wizard to update your profile.");
        }
    }

    Ok(DeploySummary {
        skills_deployed,
        hooks_deployed,
        mcp_registered,
        permissions_applied,
        output_lines,
    })
}

pub fn run(args: Cli) -> Result<()> {
    let include = normalize_list(&args.include);
    let exclude = normalize_list(&args.exclude);
    let teardown_mcp_names = normalize_list(&args.teardown_mcp);

    // --- Validate mutually exclusive / conflicting flags ---
    if args.global_flag && args.project.is_some() {
        eprintln!("Error: --global and --project are mutually exclusive");
        std::process::exit(1);
    }

    if args.project.is_some() && args.on_path {
        eprintln!("Error: --on-path is not supported with --project");
        std::process::exit(1);
    }

    if !include.is_empty() && !exclude.is_empty() {
        eprintln!("Error: --include and --exclude are mutually exclusive");
        std::process::exit(1);
    }

    if let Some(ref project) = args.project {
        if !Path::new(project).is_dir() {
            eprintln!("Error: Project directory does not exist: {}", project);
            std::process::exit(1);
        }
    }

    // --- Resolve paths ---
    let repo_root = find_repo_root()?;

    let claude_config_dir = resolve_claude_config_dir();

    let mut project_path: Option<PathBuf> = args.project.as_ref().map(|p| {
        Path::new(p)
            .canonicalize()
            .unwrap_or_else(|_| PathBuf::from(p))
    });

    // --- Handle --teardown-mcp ---
    if !teardown_mcp_names.is_empty() {
        let mcp_base = repo_root.join("mcp");
        let settings_file = claude_config_dir.join("settings.json");

        if args.dry_run {
            println!("=== DRY RUN (no changes will be made) ===");
            println!();
        }

        println!("=== MCP Teardown ===");
        for name in &teardown_mcp_names {
            let mcp_dir = mcp_base.join(name);
            if !mcp_dir.is_dir() {
                println!(
                    "  Warning: mcp/{} not found, skipping teardown script",
                    name
                );
            } else {
                teardown_mcp(&mcp_dir, args.dry_run);
            }
        }

        remove_settings_mcp(&settings_file, &teardown_mcp_names, args.dry_run)?;
        return Ok(());
    }

    // --- Profile loading ---
    let profile_arg = args.profile.as_deref().unwrap_or("");
    let (profile_path, profile_data) = load_profile(profile_arg, &repo_root);

    if profile_data.is_null() {
        eprintln!("Error: Profile not found: {}", profile_arg);
        std::process::exit(1);
    }

    let profile_data_ref = if profile_data
        .as_object()
        .map(|m| m.is_empty())
        .unwrap_or(true)
    {
        Value::Object(Default::default())
    } else {
        profile_data.clone()
    };

    // If profile has project_path and CLI --project was not given, use it
    if !profile_data_ref.as_object().unwrap().is_empty() && project_path.is_none() {
        if let Some(pp) = profile_data_ref
            .get("project_path")
            .and_then(|v| v.as_str())
        {
            if !pp.is_empty() {
                let pp_path = PathBuf::from(pp);
                if !pp_path.is_dir() {
                    eprintln!("Error: Profile project directory does not exist: {}", pp);
                    std::process::exit(1);
                }
                project_path = Some(pp_path);
            }
        }
    }

    // --- Discover mode ---
    if args.discover {
        let result = discover_items(&repo_root, &profile_data_ref);
        let mut json_val = serde_json::to_value(&result)?;
        if !profile_data_ref.as_object().unwrap().is_empty() {
            let diff = profile_diff(&result, &profile_data_ref);
            json_val
                .as_object_mut()
                .unwrap()
                .insert("profile_diff".to_string(), serde_json::to_value(&diff)?);
        }
        println!("{}", serde_json::to_string_pretty(&json_val)?);
        return Ok(());
    }

    // --- Build context and execute ---
    let ctx = DeployContext {
        repo_root,
        claude_config_dir,
        project_path,
        on_path: args.on_path,
        dry_run: args.dry_run,
        skip_permissions: args.skip_permissions,
        include,
        exclude,
        profile_data: profile_data_ref.clone(),
        quiet: false,
        on_path_scripts: HashMap::new(),
    };

    let summary = execute_deploy(&ctx)?;

    if ctx.on_path {
        // Already printed in execute_deploy
    }

    if !profile_path.is_empty() {
        println!("Profile loaded: {}", profile_path);
    }

    let _ = summary; // summary is printed inline by execute_deploy

    Ok(())
}

/// Find the repository root by looking for skills/ directory.
pub fn find_repo_root() -> Result<PathBuf> {
    // First try: current working directory and its ancestors
    let cwd = std::env::current_dir()?;
    for ancestor in cwd.ancestors() {
        if ancestor.join("skills").is_dir() {
            return Ok(ancestor.to_path_buf());
        }
    }

    // Fallback: relative to the executable
    let exe = std::env::current_exe()?;
    let exe_parent = exe.parent().unwrap();
    for ancestor in exe_parent.ancestors() {
        if ancestor.join("skills").is_dir() {
            return Ok(ancestor.to_path_buf());
        }
    }

    anyhow::bail!("Could not find repository root (no skills/ directory found)")
}

/// Resolve the Claude config directory (respects CLAUDE_CONFIG_DIR env var).
pub fn resolve_claude_config_dir() -> PathBuf {
    std::env::var("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| dirs::home_dir().unwrap().join(".claude"))
}
