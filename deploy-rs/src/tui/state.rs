// tui/state.rs - Persistent TUI state

use super::app::{App, AssignedMode, ProjectEntry};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

const STATE_FILE: &str = ".deploy-tui-state.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TuiState {
    #[serde(default)]
    pub projects: Vec<ProjectState>,
    #[serde(default)]
    pub assignments: HashMap<String, AssignmentState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectState {
    pub path: PathBuf,
    pub alias: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssignmentState {
    pub mode: String, // "global", "project", "skip"
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub projects: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub on_path_scripts: Vec<String>,
}

/// Load state from the repo root's state file.
pub fn load_state(repo_root: &Path) -> Option<TuiState> {
    let path = repo_root.join(STATE_FILE);
    if !path.exists() {
        return None;
    }
    let content = std::fs::read_to_string(&path).ok()?;
    serde_json::from_str(&content).ok()
}

/// Save state to the repo root's state file.
pub fn save_state(repo_root: &Path, state: &TuiState) -> Result<()> {
    let path = repo_root.join(STATE_FILE);
    let content = serde_json::to_string_pretty(state)?;
    std::fs::write(&path, content)?;
    Ok(())
}

/// Apply loaded state to the App, restoring selections.
pub fn apply_state(app: &mut App, state: &TuiState) {
    // Restore projects (only those whose paths still exist)
    app.projects.clear();
    for ps in &state.projects {
        if ps.path.is_dir() {
            app.projects.push(ProjectEntry {
                path: ps.path.clone(),
                alias: ps.alias.clone(),
            });
        }
    }

    // Build set of valid aliases
    let valid_aliases: Vec<String> = app.projects.iter().map(|p| p.alias.clone()).collect();

    // Restore assignments
    for (name, assignment) in &state.assignments {
        let mode = match assignment.mode.as_str() {
            "global" => AssignedMode::Global,
            "project" => {
                let aliases: Vec<String> = assignment
                    .projects
                    .iter()
                    .filter(|a| valid_aliases.contains(a))
                    .cloned()
                    .collect();
                if aliases.is_empty() {
                    AssignedMode::Skip
                } else {
                    AssignedMode::Project(aliases)
                }
            }
            "skip" => AssignedMode::Skip,
            _ => continue,
        };

        let on_path_scripts: Vec<&str> = assignment
            .on_path_scripts
            .iter()
            .map(|s| s.as_str())
            .collect();

        // Try to match against skills
        if let Some(skill) = app.skill_rows.iter_mut().find(|s| s.name == *name) {
            if skill.enabled {
                skill.mode = mode.clone();
                // Restore per-script PATH (only if Global)
                if skill.mode.is_global() {
                    for script in &mut skill.scripts {
                        script.on_path = on_path_scripts.contains(&script.name.as_str());
                    }
                }
            }
            continue;
        }

        // Try hooks
        if let Some(hook) = app.hook_rows.iter_mut().find(|h| h.name == *name) {
            if hook.enabled {
                // Hooks only support Global/Skip
                hook.mode = if mode.is_global() {
                    AssignedMode::Global
                } else {
                    AssignedMode::Skip
                };
            }
            continue;
        }

        // Try MCP
        if let Some(mcp) = app.mcp_rows.iter_mut().find(|m| m.name == *name) {
            if mcp.enabled {
                mcp.mode = mode.clone();
            }
            continue;
        }

        // Try permissions
        if let Some(perm) = app.perm_rows.iter_mut().find(|p| p.name == *name) {
            if perm.enabled {
                perm.mode = mode;
            }
        }
        // Items not found on disk are silently ignored
    }
}

/// Capture current App state for persistence.
pub fn capture_state(app: &App) -> TuiState {
    let projects: Vec<ProjectState> = app
        .projects
        .iter()
        .map(|p| ProjectState {
            path: p.path.clone(),
            alias: p.alias.clone(),
        })
        .collect();

    let mut assignments = HashMap::new();

    // Skills
    for skill in &app.skill_rows {
        let (mode_str, project_aliases) = mode_to_state(&skill.mode);
        let on_path_scripts: Vec<String> = skill
            .scripts
            .iter()
            .filter(|s| s.on_path)
            .map(|s| s.name.clone())
            .collect();
        assignments.insert(
            skill.name.clone(),
            AssignmentState {
                mode: mode_str,
                projects: project_aliases,
                on_path_scripts,
            },
        );
    }

    // Hooks
    for hook in &app.hook_rows {
        let (mode_str, project_aliases) = mode_to_state(&hook.mode);
        assignments.insert(
            hook.name.clone(),
            AssignmentState {
                mode: mode_str,
                projects: project_aliases,
                on_path_scripts: Vec::new(),
            },
        );
    }

    // MCP
    for mcp in &app.mcp_rows {
        let (mode_str, project_aliases) = mode_to_state(&mcp.mode);
        assignments.insert(
            mcp.name.clone(),
            AssignmentState {
                mode: mode_str,
                projects: project_aliases,
                on_path_scripts: Vec::new(),
            },
        );
    }

    // Permissions
    for perm in &app.perm_rows {
        let (mode_str, project_aliases) = mode_to_state(&perm.mode);
        assignments.insert(
            perm.name.clone(),
            AssignmentState {
                mode: mode_str,
                projects: project_aliases,
                on_path_scripts: Vec::new(),
            },
        );
    }

    TuiState {
        projects,
        assignments,
    }
}

fn mode_to_state(mode: &AssignedMode) -> (String, Vec<String>) {
    match mode {
        AssignedMode::Global => ("global".to_string(), Vec::new()),
        AssignedMode::Project(aliases) => {
            if aliases.is_empty() {
                ("skip".to_string(), Vec::new())
            } else {
                ("project".to_string(), aliases.clone())
            }
        }
        AssignedMode::Skip => ("skip".to_string(), Vec::new()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::{DiscoverResult, DiscoveredItem};
    use crate::tui::app::{App, ScriptEntry};

    fn make_app() -> App {
        let discover = DiscoverResult {
            repo_root: "/tmp/test".to_string(),
            profiles: vec![],
            skills: vec![DiscoveredItem {
                name: "catchup".to_string(),
                enabled: true,
                scope: "global".to_string(),
                on_path: None,
                source_path: PathBuf::from("/tmp/test/catchup"),
                description: None,
            }],
            hooks: vec![DiscoveredItem {
                name: "my-hook".to_string(),
                enabled: true,
                scope: "global".to_string(),
                on_path: None,
                source_path: PathBuf::from("/tmp/test/my-hook"),
                description: None,
            }],
            mcp: vec![],
            permissions: vec![],
        };
        let mut app = App::new(
            discover,
            PathBuf::from("/tmp"),
            PathBuf::from("/tmp/.claude"),
        );
        // Add a script manually since we can't discover from /tmp
        app.skill_rows[0].scripts.push(ScriptEntry {
            name: "my-script".to_string(),
            on_path: true,
        });
        app
    }

    #[test]
    fn test_capture_and_apply_roundtrip() {
        let mut app = make_app();
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/tmp"),
            alias: "tmp".to_string(),
        });

        let state = capture_state(&app);

        // Verify capture
        assert_eq!(state.projects.len(), 1);
        assert_eq!(state.projects[0].alias, "tmp");
        let catchup = &state.assignments["catchup"];
        assert_eq!(catchup.mode, "global");
        assert_eq!(catchup.on_path_scripts, vec!["my-script"]);

        // Apply to a fresh app
        let mut app2 = make_app();
        apply_state(&mut app2, &state);

        assert_eq!(app2.projects.len(), 1);
        assert_eq!(app2.projects[0].alias, "tmp");
        assert!(app2.skill_rows[0].scripts[0].on_path);
    }

    #[test]
    fn test_stale_project_removed() {
        let state = TuiState {
            projects: vec![ProjectState {
                path: PathBuf::from("/nonexistent/path"),
                alias: "gone".to_string(),
            }],
            assignments: HashMap::new(),
        };

        let mut app = make_app();
        apply_state(&mut app, &state);

        // Stale project should be removed
        assert!(app.projects.is_empty());
    }

    #[test]
    fn test_unknown_item_ignored() {
        let mut assignments = HashMap::new();
        assignments.insert(
            "nonexistent-tool".to_string(),
            AssignmentState {
                mode: "global".to_string(),
                projects: Vec::new(),
                on_path_scripts: Vec::new(),
            },
        );
        let state = TuiState {
            projects: Vec::new(),
            assignments,
        };

        let mut app = make_app();
        apply_state(&mut app, &state);
        // Should not panic or error
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);
    }
}
