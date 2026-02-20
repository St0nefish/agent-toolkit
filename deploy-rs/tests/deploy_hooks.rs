// tests/deploy_hooks.rs - Hook registration into settings.json

mod common;
use common::MiniRepo;
use serde_json::json;

fn setup_hooks_repo() -> MiniRepo {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_hook(
        "test-hook",
        Some(&json!({
            "hooks_config": {
                "event": "PreToolUse",
                "matcher": "Bash",
                "command_script": "test-hook.sh"
            }
        })),
    );
    repo.create_hook(
        "async-hook",
        Some(&json!({
            "hooks_config": {
                "event": "PostToolUse",
                "matcher": "Edit|Write",
                "command_script": "async-hook.sh",
                "async": true,
                "timeout": 60
            }
        })),
    );
    repo.seed_settings(&json!({"env": {"TEST": "preserved"}, "model": "test-model"}));
    repo
}

#[test]
fn hooks_object_written() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    assert!(settings.get("hooks").unwrap().is_object());
}

#[test]
fn pre_tool_use_matcher_is_bash() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let entries = &settings["hooks"]["PreToolUse"];
    assert!(entries.as_array().unwrap().len() > 0);
    assert_eq!(entries[0]["matcher"], "Bash");
}

#[test]
fn pre_tool_use_command_ends_with_script() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let command = settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        .as_str()
        .unwrap();
    assert!(command.ends_with("test-hook/test-hook.sh"));
}

#[test]
fn async_hook_properties() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    let entry = &settings["hooks"]["PostToolUse"][0];
    assert_eq!(entry["matcher"], "Edit|Write");
    assert_eq!(entry["hooks"][0]["async"], true);
    assert_eq!(entry["hooks"][0]["timeout"], 60);
}

#[test]
fn other_settings_preserved() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    assert_eq!(settings["env"]["TEST"], "preserved");
    assert_eq!(settings["model"], "test-model");
}

#[test]
fn idempotent_hooks() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);
    let first = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();
    repo.run_deploy(&[]);
    let second = std::fs::read_to_string(repo.config_dir.join("settings.json")).unwrap();
    assert_eq!(first, second);
}

#[test]
fn custom_event_survives_redeploy() {
    let repo = setup_hooks_repo();
    repo.run_deploy(&[]);

    // Inject a manual hook
    let mut settings = repo.read_settings();
    settings["hooks"]["CustomEvent"] = json!([{
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "/usr/bin/true"}]
    }]);
    std::fs::write(
        repo.config_dir.join("settings.json"),
        serde_json::to_string_pretty(&settings).unwrap() + "\n",
    )
    .unwrap();

    repo.run_deploy(&[]);

    let settings_after = repo.read_settings();
    assert!(settings_after["hooks"]["CustomEvent"].is_array());
}

#[test]
fn matcherless_hook() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_hook(
        "notify-on-stop",
        Some(&json!({
            "hooks_config": [
                {
                    "event": "UserPromptSubmit",
                    "command_script": "notify-on-stop.sh",
                    "async": true
                },
                {
                    "event": "Stop",
                    "command_script": "notify-on-stop.sh",
                    "async": true
                }
            ]
        })),
    );
    repo.seed_settings(&json!({}));
    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    assert!(settings["hooks"]["UserPromptSubmit"].is_array());
    assert!(settings["hooks"]["Stop"].is_array());
    // No matcher key
    assert!(settings["hooks"]["UserPromptSubmit"][0]
        .get("matcher")
        .is_none());
    assert!(settings["hooks"]["Stop"][0].get("matcher").is_none());
}
