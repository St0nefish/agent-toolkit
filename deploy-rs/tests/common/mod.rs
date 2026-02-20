// tests/common/mod.rs - Shared test helpers (MiniRepo equivalent)
#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

/// A test helper that creates a minimal repo layout in a temp directory
/// and provides methods to run the deploy binary against it.
pub struct MiniRepo {
    pub root: PathBuf,
    pub config_dir: PathBuf,
    _root_tmp: TempDir,
    _config_tmp: TempDir,
}

impl MiniRepo {
    pub fn new() -> Self {
        let root_tmp = TempDir::new().unwrap();
        let config_tmp = TempDir::new().unwrap();

        MiniRepo {
            root: root_tmp.path().to_path_buf(),
            config_dir: config_tmp.path().to_path_buf(),
            _root_tmp: root_tmp,
            _config_tmp: config_tmp,
        }
    }

    /// Create a skill with default md and script content.
    pub fn create_skill(&self, name: &str) -> PathBuf {
        self.create_skill_full(name, None, None, None)
    }

    /// Create a skill with full options.
    pub fn create_skill_full(
        &self,
        name: &str,
        md_content: Option<&str>,
        script_content: Option<&str>,
        deploy_json: Option<&serde_json::Value>,
    ) -> PathBuf {
        let skill_dir = self.root.join("skills").join(name);
        let bin_dir = skill_dir.join("bin");
        fs::create_dir_all(&bin_dir).unwrap();

        let script = bin_dir.join(name);
        fs::write(&script, script_content.unwrap_or("#!/bin/bash\necho hello")).unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();

        let default_md = format!("---\ndescription: Test tool {}\n---\n# {}\n", name, name);
        let md = md_content.unwrap_or(&default_md);
        fs::write(skill_dir.join(format!("{}.md", name)), md).unwrap();

        if let Some(config) = deploy_json {
            fs::write(
                skill_dir.join("deploy.json"),
                serde_json::to_string_pretty(config).unwrap() + "\n",
            )
            .unwrap();
        }

        skill_dir
    }

    /// Create a skill with extra .md files.
    pub fn create_skill_with_extra_mds(&self, name: &str, extra_mds: &[(&str, &str)]) -> PathBuf {
        let skill_dir = self.create_skill(name);
        for (filename, content) in extra_mds {
            fs::write(skill_dir.join(filename), content).unwrap();
        }
        skill_dir
    }

    /// Create a hook directory with script and optional deploy.json.
    pub fn create_hook(&self, name: &str, deploy_json: Option<&serde_json::Value>) -> PathBuf {
        let hook_dir = self.root.join("hooks").join(name);
        fs::create_dir_all(&hook_dir).unwrap();

        let script = hook_dir.join(format!("{}.sh", name));
        fs::write(&script, "#!/bin/bash\nexit 0\n").unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();

        if let Some(config) = deploy_json {
            fs::write(
                hook_dir.join("deploy.json"),
                serde_json::to_string_pretty(config).unwrap() + "\n",
            )
            .unwrap();
        }

        hook_dir
    }

    /// Create an MCP server directory with deploy.json and optional setup.sh.
    pub fn create_mcp(
        &self,
        name: &str,
        deploy_json: Option<&serde_json::Value>,
        setup_sh: Option<&str>,
    ) -> PathBuf {
        let mcp_dir = self.root.join("mcp").join(name);
        fs::create_dir_all(&mcp_dir).unwrap();

        if let Some(config) = deploy_json {
            fs::write(
                mcp_dir.join("deploy.json"),
                serde_json::to_string_pretty(config).unwrap() + "\n",
            )
            .unwrap();
        }

        if let Some(script) = setup_sh {
            let path = mcp_dir.join("setup.sh");
            fs::write(&path, script).unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        }

        mcp_dir
    }

    /// Create a permission group file.
    pub fn create_permission_group(&self, name: &str, data: &serde_json::Value) -> PathBuf {
        let perm_dir = self.root.join("permissions");
        fs::create_dir_all(&perm_dir).unwrap();

        let path = perm_dir.join(format!("{}.json", name));
        fs::write(&path, serde_json::to_string_pretty(data).unwrap() + "\n").unwrap();
        path
    }

    /// Create repo-root deploy.json.
    pub fn create_deploy_json(&self, config: &serde_json::Value) {
        fs::write(
            self.root.join("deploy.json"),
            serde_json::to_string_pretty(config).unwrap() + "\n",
        )
        .unwrap();
    }

    /// Create repo-root deploy.local.json.
    pub fn create_deploy_local_json(&self, config: &serde_json::Value) {
        fs::write(
            self.root.join("deploy.local.json"),
            serde_json::to_string_pretty(config).unwrap() + "\n",
        )
        .unwrap();
    }

    /// Seed settings.json with initial content.
    pub fn seed_settings(&self, data: &serde_json::Value) {
        fs::write(
            self.config_dir.join("settings.json"),
            serde_json::to_string_pretty(data).unwrap() + "\n",
        )
        .unwrap();
    }

    /// Read settings.json from config dir.
    pub fn read_settings(&self) -> serde_json::Value {
        let path = self.config_dir.join("settings.json");
        if path.exists() {
            let content = fs::read_to_string(&path).unwrap();
            serde_json::from_str(&content).unwrap()
        } else {
            serde_json::Value::Object(Default::default())
        }
    }

    /// Run the deploy binary with given args.
    pub fn run_deploy(&self, args: &[&str]) -> Output {
        self.run_deploy_with_env(args, &[])
    }

    /// Run the deploy binary with given args and extra env vars.
    pub fn run_deploy_with_env(&self, args: &[&str], env_overrides: &[(&str, &str)]) -> Output {
        let binary = deploy_binary_path();

        let mut cmd = Command::new(&binary);
        cmd.args(args)
            .current_dir(&self.root)
            .env("CLAUDE_CONFIG_DIR", &self.config_dir);

        for (key, val) in env_overrides {
            cmd.env(key, val);
        }

        cmd.output().unwrap_or_else(|e| {
            panic!("Failed to run deploy binary at {}: {}", binary.display(), e)
        })
    }

    /// Get stdout from a deploy run as String.
    pub fn run_deploy_stdout(&self, args: &[&str]) -> String {
        let output = self.run_deploy(args);
        String::from_utf8_lossy(&output.stdout).to_string()
    }
}

/// Find the deploy binary path (built by cargo).
fn deploy_binary_path() -> PathBuf {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));

    // Try debug first, then release
    for profile in &["debug", "release"] {
        let path = manifest_dir.join("target").join(profile).join("deploy");
        if path.exists() {
            return path;
        }
    }

    // Fallback: use cargo to find it
    let output = Command::new("cargo")
        .args(["build", "--manifest-path"])
        .arg(manifest_dir.join("Cargo.toml"))
        .output()
        .expect("Failed to build deploy binary");

    if !output.status.success() {
        panic!(
            "cargo build failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    manifest_dir.join("target").join("debug").join("deploy")
}
