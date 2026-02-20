// tests/deploy_mcp.rs - MCP server deployment tests

mod common;
use common::MiniRepo;
use serde_json::json;

#[test]
fn mcp_deployed_message() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {
                "command": "docker",
                "args": ["run", "--rm", "-i", "test-image:latest"],
                "env": {}
            }
        })),
        None,
    );
    repo.seed_settings(&json!({}));

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("Deployed: test-mcp"));
}

#[test]
fn mcp_registered_in_settings() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {
                "command": "docker",
                "args": ["run", "--rm", "-i", "test-image:latest"],
                "env": {}
            }
        })),
        None,
    );
    repo.seed_settings(&json!({"env": {"TEST": "preserved"}}));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    assert!(settings["mcpServers"]["test-mcp"].is_object());
    assert_eq!(settings["mcpServers"]["test-mcp"]["command"], "docker");
    assert_eq!(settings["env"]["TEST"], "preserved");
}

#[test]
fn mcp_missing_key_skips() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp("bad-mcp", Some(&json!({"enabled": true})), None);

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("'mcp' key must have 'command' or 'url'"));
}

#[test]
fn mcp_url_based_deploys() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "url-mcp",
        Some(&json!({
            "mcp": {"url": "https://mcp.example.com/mcp"}
        })),
        None,
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);

    let settings = repo.read_settings();
    assert_eq!(
        settings["mcpServers"]["url-mcp"]["url"],
        "https://mcp.example.com/mcp"
    );
}

#[test]
fn mcp_exclude_filters() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        None,
    );

    let stdout = repo.run_deploy_stdout(&["--exclude", "test-mcp"]);
    assert!(stdout.contains("Skipped: test-mcp (filtered out)"));
}

#[test]
fn mcp_disabled_skips() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "disabled-mcp",
        Some(&json!({
            "enabled": false,
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        None,
    );

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("Skipped: disabled-mcp (disabled by config)"));
}

#[test]
fn setup_sh_runs_on_deploy() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        Some("#!/usr/bin/env bash\necho 'setup ok'\n"),
    );
    repo.seed_settings(&json!({}));

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("setup ok"));
}

#[test]
fn setup_sh_failure_warns() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "fail-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        Some("#!/usr/bin/env bash\necho 'failing' >&2\nexit 1\n"),
    );

    let stdout = repo.run_deploy_stdout(&[]);
    assert!(stdout.contains("setup.sh failed"));
}

#[test]
fn mcp_append_missing_preserves_existing() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        None,
    );
    repo.seed_settings(&json!({}));

    repo.run_deploy(&[]);

    // Inject a manual server
    let mut settings = repo.read_settings();
    settings["mcpServers"]["manual-server"] = json!({"command": "npx", "args": ["manual"]});
    std::fs::write(
        repo.config_dir.join("settings.json"),
        serde_json::to_string_pretty(&settings).unwrap() + "\n",
    )
    .unwrap();

    repo.run_deploy(&[]);

    let settings_after = repo.read_settings();
    assert!(settings_after["mcpServers"]["manual-server"].is_object());
    assert!(settings_after["mcpServers"]["test-mcp"].is_object());
}

#[test]
fn project_writes_mcp_json() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        None,
    );

    let project_dir = tempfile::TempDir::new().unwrap();
    repo.run_deploy(&["--project", project_dir.path().to_str().unwrap()]);

    let mcp_json: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(project_dir.path().join(".mcp.json")).unwrap(),
    )
    .unwrap();
    assert!(mcp_json["mcpServers"]["test-mcp"].is_object());
}

#[test]
fn teardown_mcp_removes_from_settings() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_mcp(
        "test-mcp",
        Some(&json!({
            "mcp": {"command": "docker", "args": ["run", "test"]}
        })),
        None,
    );
    repo.seed_settings(&json!({}));

    // Deploy first
    repo.run_deploy(&[]);
    let settings = repo.read_settings();
    assert!(settings["mcpServers"]["test-mcp"].is_object());

    // Teardown
    repo.run_deploy(&["--teardown-mcp", "test-mcp"]);
    let settings_after = repo.read_settings();
    assert!(settings_after["mcpServers"].get("test-mcp").is_none());
}
