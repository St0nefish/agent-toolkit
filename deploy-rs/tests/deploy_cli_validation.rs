// tests/deploy_cli_validation.rs - CLI flag validation tests

mod common;
use common::MiniRepo;

#[test]
fn include_and_exclude_mutually_exclusive() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");

    let output = repo.run_deploy(&["--include", "alpha", "--exclude", "beta"]);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("mutually exclusive") || !output.status.success(),
        "Expected error for --include + --exclude, got: {}",
        stderr
    );
}

#[test]
fn project_and_on_path_incompatible() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    let project_dir = tempfile::TempDir::new().unwrap();

    let output = repo.run_deploy(&[
        "--project",
        project_dir.path().to_str().unwrap(),
        "--on-path",
    ]);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("not supported with --project") || !output.status.success(),
        "Expected error for --project + --on-path, got: {}",
        stderr
    );
}

#[test]
fn nonexistent_project_path_errors() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");

    let output = repo.run_deploy(&["--project", "/nonexistent/path/to/project"]);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("does not exist") || !output.status.success(),
        "Expected error for nonexistent project, got: {}",
        stderr
    );
}
