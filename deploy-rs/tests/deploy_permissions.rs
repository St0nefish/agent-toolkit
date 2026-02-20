// tests/deploy_permissions.rs - Permission management tests

mod common;
use common::MiniRepo;
use serde_json::json;

#[test]
fn permissions_written_to_settings() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "alpha",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(alpha)", "Bash(alpha *)"],
                "deny": []
            }
        })),
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let allows = settings["permissions"]["allow"].as_array().unwrap();
    assert!(allows.iter().any(|v| v.as_str() == Some("Bash(alpha)")));
}

#[test]
fn deny_entries_written() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "alpha",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(alpha)"],
                "deny": ["Bash(rm -rf *)"]
            }
        })),
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let denies = settings["permissions"]["deny"].as_array().unwrap();
    assert!(denies.iter().any(|v| v.as_str() == Some("Bash(rm -rf *)")));
}

#[test]
fn permissions_idempotent() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "alpha",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(alpha)"],
                "deny": []
            }
        })),
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);
    let first = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();
    repo.run_deploy(&[]);
    let second = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();
    assert_eq!(first, second);
}

#[test]
fn append_missing_preserves_manual_entries() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "alpha",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(alpha)"],
                "deny": []
            }
        })),
    );
    repo.seed_settings(&json!({
        "permissions": {
            "allow": ["Bash(manual-entry)"],
            "deny": []
        }
    }));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let allows = settings["permissions"]["allow"].as_array().unwrap();
    assert!(allows
        .iter()
        .any(|v| v.as_str() == Some("Bash(manual-entry)")));
    assert!(allows.iter().any(|v| v.as_str() == Some("Bash(alpha)")));
}

#[test]
fn skip_permissions_message() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");

    let stdout = repo.run_deploy_stdout(&["--skip-permissions"]);
    assert!(stdout.contains("Skipped: permissions management (--skip-permissions)"));
}

#[test]
fn dry_run_no_settings_change() {
    let repo = MiniRepo::new();
    repo.create_skill_full(
        "alpha",
        None,
        None,
        Some(&json!({
            "permissions": {
                "allow": ["Bash(alpha)"],
                "deny": []
            }
        })),
    );
    repo.seed_settings(&json!({}));
    let before = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();

    repo.run_deploy(&["--dry-run"]);

    let after = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();
    assert_eq!(before, after);
}
