// tests/deploy_filtering.rs - Include/exclude and enabled config tests

mod common;
use common::MiniRepo;
use serde_json::json;

#[test]
fn include_deploys_only_named_tool() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.create_skill("beta");
    repo.create_skill("gamma");

    repo.run_deploy(&["--include", "alpha", "--skip-permissions"]);

    assert!(repo.config_dir.join("tools/alpha").is_symlink());
    assert!(!repo.config_dir.join("tools/beta").exists());
    assert!(!repo.config_dir.join("tools/gamma").exists());
}

#[test]
fn include_emits_filtered_message() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.create_skill("beta");

    let stdout = repo.run_deploy_stdout(&["--include", "alpha", "--skip-permissions"]);
    assert!(stdout.contains("Skipped: beta (filtered out)"));
}

#[test]
fn exclude_deploys_non_excluded() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.create_skill("beta");
    repo.create_skill("gamma");

    repo.run_deploy(&["--exclude", "beta", "--skip-permissions"]);

    assert!(repo.config_dir.join("tools/alpha").is_symlink());
    assert!(!repo.config_dir.join("tools/beta").exists());
    assert!(repo.config_dir.join("tools/gamma").is_symlink());
}

#[test]
fn exclude_emits_filtered_message() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.create_skill("beta");

    let stdout = repo.run_deploy_stdout(&["--exclude", "beta", "--skip-permissions"]);
    assert!(stdout.contains("Skipped: beta (filtered out)"));
}

#[test]
fn disabled_tool_not_deployed() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.create_skill_full("beta", None, None, Some(&json!({"enabled": false})));

    repo.run_deploy(&["--skip-permissions"]);

    assert!(repo.config_dir.join("tools/alpha").is_symlink());
    assert!(!repo.config_dir.join("tools/beta").exists());
}

#[test]
fn disabled_tool_emits_message() {
    let repo = MiniRepo::new();
    repo.create_skill_full("beta", None, None, Some(&json!({"enabled": false})));

    let stdout = repo.run_deploy_stdout(&["--skip-permissions"]);
    assert!(stdout.contains("Skipped: beta (disabled by config)"));
}

#[test]
fn exclude_filters_hook() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_hook("test-hook", None);

    let stdout = repo.run_deploy_stdout(&["--exclude", "test-hook", "--skip-permissions"]);
    assert!(stdout.contains("Skipped: hook test-hook (filtered out)"));
    assert!(!repo.config_dir.join("hooks/test-hook").exists());
}

#[test]
fn hook_deployed_without_exclude() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_hook("test-hook", None);

    repo.run_deploy(&["--skip-permissions"]);
    assert!(repo.config_dir.join("hooks/test-hook").is_symlink());
}
