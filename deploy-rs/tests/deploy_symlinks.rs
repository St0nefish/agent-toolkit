// tests/deploy_symlinks.rs - Symlink creation and layout tests

mod common;
use common::MiniRepo;
use std::fs;

#[test]
fn single_md_creates_skill_symlink() {
    let repo = MiniRepo::new();
    repo.create_skill("single");
    repo.run_deploy(&["--skip-permissions"]);
    assert!(repo.config_dir.join("skills/single/SKILL.md").is_symlink());
}

#[test]
fn multi_md_creates_start_skill() {
    let repo = MiniRepo::new();
    let skill_dir = repo.root.join("skills/multi");
    let bin_dir = skill_dir.join("bin");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::write(bin_dir.join("multi"), "#!/bin/bash\necho hello").unwrap();
    fs::write(
        skill_dir.join("start.md"),
        "---\ndescription: Start\n---\n# Start\n",
    )
    .unwrap();
    fs::write(
        skill_dir.join("stop.md"),
        "---\ndescription: Stop\n---\n# Stop\n",
    )
    .unwrap();

    repo.run_deploy(&["--skip-permissions"]);

    assert!(repo
        .config_dir
        .join("skills/multi-start/SKILL.md")
        .is_symlink());
    assert!(repo
        .config_dir
        .join("skills/multi-stop/SKILL.md")
        .is_symlink());
}

#[test]
fn readme_excluded_from_skills() {
    let repo = MiniRepo::new();
    let skill_dir = repo.create_skill("with-readme");
    fs::write(skill_dir.join("README.md"), "# Developer notes\n").unwrap();

    repo.run_deploy(&["--skip-permissions"]);

    assert!(!repo
        .config_dir
        .join("skills/with-readme-README/SKILL.md")
        .exists());
    assert!(repo
        .config_dir
        .join("skills/with-readme/SKILL.md")
        .is_symlink());
}

#[test]
fn tool_dirs_symlinked() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    repo.run_deploy(&["--skip-permissions"]);
    assert!(repo.config_dir.join("tools/alpha").is_symlink());
}

#[test]
fn hook_dir_symlinked() {
    let repo = MiniRepo::new();
    repo.create_skill("dummy");
    repo.create_hook("test-hook", None);
    repo.run_deploy(&["--skip-permissions"]);
    assert!(repo.config_dir.join("hooks/test-hook").is_symlink());
}

#[test]
fn modern_layout_deployed() {
    let repo = MiniRepo::new();
    let group = repo.root.join("skills/workflow");
    fs::create_dir_all(group.join("start")).unwrap();
    fs::write(
        group.join("start/SKILL.md"),
        "---\ndescription: Start\n---\n# Start\n",
    )
    .unwrap();
    fs::create_dir_all(group.join("finish")).unwrap();
    fs::write(
        group.join("finish/SKILL.md"),
        "---\ndescription: Finish\n---\n# Finish\n",
    )
    .unwrap();
    fs::create_dir_all(group.join("bin")).unwrap();
    fs::write(group.join("bin/workflow"), "#!/bin/bash").unwrap();

    repo.run_deploy(&["--skip-permissions"]);

    assert!(repo
        .config_dir
        .join("skills/workflow-start/SKILL.md")
        .is_symlink());
    assert!(repo
        .config_dir
        .join("skills/workflow-finish/SKILL.md")
        .is_symlink());
    assert!(repo.config_dir.join("tools/workflow").is_symlink());
    // bin/ should not be treated as a skill
    assert!(!repo
        .config_dir
        .join("skills/workflow-bin/SKILL.md")
        .exists());
}

#[test]
fn mixed_layout_modern_wins() {
    let repo = MiniRepo::new();
    let group = repo.root.join("skills/mixed");
    fs::create_dir_all(&group).unwrap();
    fs::write(
        group.join("legacy.md"),
        "---\ndescription: Legacy\n---\n# Legacy\n",
    )
    .unwrap();
    fs::create_dir_all(group.join("modern")).unwrap();
    fs::write(
        group.join("modern/SKILL.md"),
        "---\ndescription: Modern\n---\n# Modern\n",
    )
    .unwrap();

    repo.run_deploy(&["--skip-permissions"]);

    assert!(repo
        .config_dir
        .join("skills/mixed-modern/SKILL.md")
        .is_symlink());
    assert!(!repo
        .config_dir
        .join("skills/mixed-legacy/SKILL.md")
        .exists());
}

#[test]
fn project_deploys_skills_to_project_path() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");

    let project_dir = tempfile::TempDir::new().unwrap();
    repo.run_deploy(&[
        "--project",
        project_dir.path().to_str().unwrap(),
        "--skip-permissions",
    ]);

    // Skills go to project
    assert!(project_dir
        .path()
        .join(".claude/skills/alpha/SKILL.md")
        .is_symlink());
    // Tool dirs still global
    assert!(repo.config_dir.join("tools/alpha").is_symlink());
    // Skills NOT in global
    assert!(!repo.config_dir.join("skills/alpha/SKILL.md").exists());
}

#[test]
fn dry_run_creates_no_symlinks() {
    let repo = MiniRepo::new();
    repo.create_skill("alpha");
    let output = repo.run_deploy(&["--dry-run", "--skip-permissions"]);
    let stdout = String::from_utf8_lossy(&output.stdout);

    assert!(!repo.config_dir.join("tools/alpha").is_symlink());
    assert!(!repo.config_dir.join("skills/alpha/SKILL.md").exists());
    assert!(stdout.contains("DRY RUN"));
    assert!(stdout.contains("> "));
}
