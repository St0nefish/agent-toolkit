// tests/deploy_config.rs - Config layer merging tests

mod common;
use common::MiniRepo;
use serde_json::json;
use std::fs;

#[test]
fn tool_deploy_json_overrides_repo_root() {
    let repo = MiniRepo::new();
    repo.create_deploy_json(&json!({"on_path": false}));
    let skill_dir = repo.create_skill("configtest");
    fs::write(
        skill_dir.join("deploy.json"),
        serde_json::to_string_pretty(&json!({"on_path": true})).unwrap() + "\n",
    )
    .unwrap();

    let fake_home = tempfile::TempDir::new().unwrap();
    repo.run_deploy_with_env(
        &["--skip-permissions"],
        &[("HOME", fake_home.path().to_str().unwrap())],
    );

    assert!(fake_home.path().join(".local/bin/configtest").is_symlink());
}

#[test]
fn deploy_local_json_overrides_deploy_json() {
    let repo = MiniRepo::new();
    let skill_dir = repo.create_skill("configtest");
    fs::write(
        skill_dir.join("deploy.json"),
        serde_json::to_string_pretty(&json!({"enabled": true})).unwrap(),
    )
    .unwrap();
    fs::write(
        skill_dir.join("deploy.local.json"),
        serde_json::to_string_pretty(&json!({"enabled": false})).unwrap(),
    )
    .unwrap();

    let stdout = repo.run_deploy_stdout(&["--skip-permissions"]);
    assert!(stdout.contains("Skipped: configtest (disabled by config)"));
}

#[test]
fn on_path_true_in_config_without_cli_flag() {
    let repo = MiniRepo::new();
    repo.create_skill_full("configtest", None, None, Some(&json!({"on_path": true})));

    let fake_home = tempfile::TempDir::new().unwrap();
    repo.run_deploy_with_env(
        &["--skip-permissions"],
        &[("HOME", fake_home.path().to_str().unwrap())],
    );

    assert!(fake_home.path().join(".local/bin/configtest").is_symlink());
}

#[test]
fn scope_project_skips_without_project_flag() {
    let repo = MiniRepo::new();
    repo.create_skill_full("configtest", None, None, Some(&json!({"scope": "project"})));

    let stdout = repo.run_deploy_stdout(&["--skip-permissions"]);
    assert!(stdout.contains("Skipped: configtest (scope=project, no --project flag given)"));
}

#[test]
fn cli_on_path_overrides_config() {
    let repo = MiniRepo::new();
    repo.create_skill_full("configtest", None, None, Some(&json!({"on_path": false})));

    let fake_home = tempfile::TempDir::new().unwrap();
    repo.run_deploy_with_env(
        &["--on-path", "--skip-permissions"],
        &[("HOME", fake_home.path().to_str().unwrap())],
    );

    assert!(fake_home.path().join(".local/bin/configtest").is_symlink());
}

#[test]
fn repo_root_deploy_local_overrides_deploy() {
    let repo = MiniRepo::new();
    repo.create_skill("configtest");
    repo.create_deploy_json(&json!({"on_path": true}));
    repo.create_deploy_local_json(&json!({"on_path": false}));

    let fake_home = tempfile::TempDir::new().unwrap();
    repo.run_deploy_with_env(
        &["--skip-permissions"],
        &[("HOME", fake_home.path().to_str().unwrap())],
    );

    assert!(!fake_home.path().join(".local/bin/configtest").is_symlink());
}
