// tests/deploy_dependencies.rs - Skill dependency tests

mod common;
use common::MiniRepo;
use serde_json::json;

#[test]
fn dependency_tool_dir_symlinked() {
    let repo = MiniRepo::new();
    // Create the dependency skill
    repo.create_skill_full(
        "dep-tool",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(dep-tool)"],
                "deny": []
            }
        })),
    );
    // Create the main skill that depends on dep-tool
    repo.create_skill_full(
        "main-tool",
        None,
        None,
        Some(&json!({"dependencies": ["dep-tool"]})),
    );

    repo.run_deploy(&["--skip-permissions"]);

    // Both tool dirs should exist
    assert!(repo.config_dir.join("tools/main-tool").is_symlink());
    assert!(repo.config_dir.join("tools/dep-tool").is_symlink());
}

#[test]
fn dependency_skill_not_deployed() {
    let repo = MiniRepo::new();
    repo.create_skill("dep-tool");
    repo.create_skill_full(
        "main-tool",
        None,
        None,
        Some(&json!({"dependencies": ["dep-tool"]})),
    );

    // Deploy only main-tool
    repo.run_deploy(&["--include", "main-tool", "--skip-permissions"]);

    // dep-tool's tool dir should be linked (as dependency)
    assert!(repo.config_dir.join("tools/dep-tool").is_symlink());
    // But dep-tool's skill should NOT be deployed
    assert!(!repo.config_dir.join("skills/dep-tool/SKILL.md").exists());
}

#[test]
fn missing_dependency_warns() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "main-tool",
        None,
        None,
        Some(&json!({"dependencies": ["nonexistent"]})),
    );

    let stdout = repo.run_deploy_stdout(&["--skip-permissions"]);
    assert!(stdout.contains("Warning: dependency 'nonexistent' not found"));
}
