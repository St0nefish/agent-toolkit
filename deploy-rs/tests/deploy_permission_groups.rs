// tests/deploy_permission_groups.rs - Permission group file tests

mod common;
use common::MiniRepo;
use serde_json::json;

#[test]
fn permission_group_contributes_allow_entries() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_permission_group(
        "git",
        &json!({
            "permissions": {
                "allow": ["Bash(git status)", "Bash(git log *)"]
            }
        }),
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let allows = settings["permissions"]["allow"].as_array().unwrap();
    assert!(allows
        .iter()
        .any(|v| v.as_str() == Some("Bash(git status)")));
    assert!(allows.iter().any(|v| v.as_str() == Some("Bash(git log *)")));
}

#[test]
fn disabled_permission_group_skipped() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_permission_group(
        "git",
        &json!({
            "enabled": false,
            "permissions": {
                "allow": ["Bash(git status)"]
            }
        }),
    );
    repo.seed_settings(&json!({}));

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("Skipped: git (disabled)"));
}

#[test]
fn include_filters_permission_group() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_permission_group(
        "git",
        &json!({
            "permissions": { "allow": ["Bash(git status)"] }
        }),
    );
    repo.create_permission_group(
        "docker",
        &json!({
            "permissions": { "allow": ["Bash(docker ps)"] }
        }),
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&["--include", "dummy", "git"]);

    let settings = repo.read_settings();
    let allows = settings["permissions"]["allow"].as_array().unwrap();
    assert!(allows
        .iter()
        .any(|v| v.as_str() == Some("Bash(git status)")));
    // docker should be filtered out
    assert!(!allows.iter().any(|v| v.as_str() == Some("Bash(docker ps)")));
}

#[test]
fn no_permissions_dir_is_ok() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    // No permissions/ directory created
    repo.seed_settings(&json!({}));

    let output = repo.run_deploy(&[]);
    assert!(output.status.success());
}
