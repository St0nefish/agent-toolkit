// permissions.rs - Permission collection and sort-key table

use crate::config::load_json;
use std::path::Path;

/// Permission sort groups for visual grouping in settings.json.
const PERMISSION_GROUPS: &[(&str, &str)] = &[
    ("Bash(cat", "01-bash-read"),
    ("Bash(column", "01-bash-read"),
    ("Bash(cut", "01-bash-read"),
    ("Bash(diff", "01-bash-read"),
    ("Bash(file", "01-bash-read"),
    ("Bash(find", "01-bash-read"),
    ("Bash(grep", "01-bash-read"),
    ("Bash(head", "01-bash-read"),
    ("Bash(jq", "01-bash-read"),
    ("Bash(ls", "01-bash-read"),
    ("Bash(md5sum", "01-bash-read"),
    ("Bash(readlink", "01-bash-read"),
    ("Bash(realpath", "01-bash-read"),
    ("Bash(rg", "01-bash-read"),
    ("Bash(sha256sum", "01-bash-read"),
    ("Bash(sort", "01-bash-read"),
    ("Bash(stat", "01-bash-read"),
    ("Bash(tail", "01-bash-read"),
    ("Bash(tar", "01-bash-read"),
    ("Bash(test", "01-bash-read"),
    ("Bash(tr", "01-bash-read"),
    ("Bash(tree", "01-bash-read"),
    ("Bash(uniq", "01-bash-read"),
    ("Bash(unzip", "01-bash-read"),
    ("Bash(wc", "01-bash-read"),
    ("Bash(which", "01-bash-read"),
    ("Bash(zip", "01-bash-read"),
    ("Bash(date", "02-system"),
    ("Bash(df", "02-system"),
    ("Bash(du", "02-system"),
    ("Bash(hostname", "02-system"),
    ("Bash(id", "02-system"),
    ("Bash(lsof", "02-system"),
    ("Bash(netstat", "02-system"),
    ("Bash(printenv", "02-system"),
    ("Bash(ps", "02-system"),
    ("Bash(pwd", "02-system"),
    ("Bash(ss", "02-system"),
    ("Bash(top", "02-system"),
    ("Bash(uname", "02-system"),
    ("Bash(uptime", "02-system"),
    ("Bash(whoami", "02-system"),
    ("Bash(git ", "03-git"),
    ("Bash(docker", "04-docker"),
    ("Bash(gh ", "05-github"),
    ("Bash(python", "06-python"),
    ("Bash(python3", "06-python"),
    ("Bash(pip", "06-python"),
    ("Bash(pip3", "06-python"),
    ("Bash(uv ", "06-python"),
    ("Bash(poetry", "06-python"),
    ("Bash(pyenv", "06-python"),
    ("Bash(pipenv", "06-python"),
    ("Bash(node", "07-node"),
    ("Bash(npm", "07-node"),
    ("Bash(npx", "07-node"),
    ("Bash(yarn", "07-node"),
    ("Bash(pnpm", "07-node"),
    ("Bash(nvm", "07-node"),
    ("Bash(deno", "07-node"),
    ("Bash(java", "08-jvm"),
    ("Bash(javac", "08-jvm"),
    ("Bash(javap", "08-jvm"),
    ("Bash(jar ", "08-jvm"),
    ("Bash(gradle", "08-jvm"),
    ("Bash(./gradlew", "08-jvm"),
    ("Bash(mvn", "08-jvm"),
    ("Bash(kotlin", "08-jvm"),
    ("Bash(rustc", "09-rust"),
    ("Bash(rustup", "09-rust"),
    ("Bash(cargo", "09-rust"),
    ("Bash(~/.claude/tools/", "10-tools"),
    ("Bash(command", "10-tools"),
    ("WebFetch", "11-web"),
];

/// Sort key for permissions - groups related entries together.
pub fn permission_sort_key(entry: &str) -> (String, String) {
    for (prefix, group) in PERMISSION_GROUPS {
        if entry.starts_with(prefix) {
            return (group.to_string(), entry.to_string());
        }
    }
    ("99-other".to_string(), entry.to_string())
}

/// Gather all permission entries from a list of config file paths.
///
/// Returns (allows, denies) as sorted, deduplicated vectors.
pub fn collect_permissions(config_files: &[&Path]) -> (Vec<String>, Vec<String>) {
    use std::collections::BTreeSet;

    let mut all_allows = BTreeSet::new();
    let mut all_denies = BTreeSet::new();

    for path in config_files {
        let data = load_json(path);
        if let Some(perms) = data.get("permissions").and_then(|v| v.as_object()) {
            if let Some(allow_arr) = perms.get("allow").and_then(|v| v.as_array()) {
                for entry in allow_arr {
                    if let Some(s) = entry.as_str() {
                        if !s.is_empty() {
                            all_allows.insert(s.to_string());
                        }
                    }
                }
            }
            if let Some(deny_arr) = perms.get("deny").and_then(|v| v.as_array()) {
                for entry in deny_arr {
                    if let Some(s) = entry.as_str() {
                        if !s.is_empty() {
                            all_denies.insert(s.to_string());
                        }
                    }
                }
            }
        }
    }

    let mut allows: Vec<String> = all_allows.into_iter().collect();
    let mut denies: Vec<String> = all_denies.into_iter().collect();

    allows.sort_by_key(|a| permission_sort_key(a));
    denies.sort_by_key(|a| permission_sort_key(a));

    (allows, denies)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_permission_sort_key_groups() {
        let (group, _) = permission_sort_key("Bash(git status)");
        assert_eq!(group, "03-git");

        let (group, _) = permission_sort_key("Bash(cat foo)");
        assert_eq!(group, "01-bash-read");

        let (group, _) = permission_sort_key("SomeOtherTool");
        assert_eq!(group, "99-other");
    }

    #[test]
    fn test_collect_permissions_empty() {
        let (allows, denies) = collect_permissions(&[]);
        assert!(allows.is_empty());
        assert!(denies.is_empty());
    }
}
