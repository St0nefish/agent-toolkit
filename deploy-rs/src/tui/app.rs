// tui/app.rs - Pure state machine for TUI (no terminal dependency)

use crate::discovery::{DiscoverResult, DiscoveredItem};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

/// Expand `~` prefix to home directory.
pub fn expand_tilde(path: &str) -> PathBuf {
    if path.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            return PathBuf::from(path.replacen('~', &home.to_string_lossy(), 1));
        }
    }
    PathBuf::from(path)
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

pub const TAB_SKILLS: usize = 0;
pub const TAB_HOOKS: usize = 1;
pub const TAB_MCP: usize = 2;
pub const TAB_PERMISSIONS: usize = 3;
pub const TAB_PROJECTS: usize = 4;
pub const TAB_COUNT: usize = 5;

pub const TAB_NAMES: [&str; TAB_COUNT] = ["Skills", "Hooks", "MCP", "Permissions", "Projects"];

// ---------------------------------------------------------------------------
// Assignment model
// ---------------------------------------------------------------------------

/// How an item is assigned for deployment.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AssignedMode {
    Global,
    Project(Vec<String>), // list of project aliases
    Skip,
}

impl AssignedMode {
    /// Display badge text for the mode column.
    pub fn badge(&self) -> String {
        match self {
            AssignedMode::Global => "GLOBAL".to_string(),
            AssignedMode::Project(_) => "PROJECT".to_string(),
            AssignedMode::Skip => "SKIP".to_string(),
        }
    }

    /// Display project aliases for the right column.
    pub fn project_label(&self) -> Option<String> {
        match self {
            AssignedMode::Project(aliases) if !aliases.is_empty() => Some(aliases.join(", ")),
            _ => None,
        }
    }

    #[allow(dead_code)]
    pub fn is_skip(&self) -> bool {
        matches!(self, AssignedMode::Skip)
            || matches!(self, AssignedMode::Project(a) if a.is_empty())
    }

    pub fn is_global(&self) -> bool {
        matches!(self, AssignedMode::Global)
    }
}

// ---------------------------------------------------------------------------
// Item category (kept for deploy result parsing)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Category {
    Skills,
    Hooks,
    Mcp,
    Permissions,
}

impl std::fmt::Display for Category {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Category::Skills => write!(f, "SKILLS"),
            Category::Hooks => write!(f, "HOOKS"),
            Category::Mcp => write!(f, "MCP"),
            Category::Permissions => write!(f, "PERMISSIONS"),
        }
    }
}

// ---------------------------------------------------------------------------
// Row types for each tab
// ---------------------------------------------------------------------------

/// A script inside a skill's bin/ directory.
#[derive(Clone, Debug)]
pub struct ScriptEntry {
    pub name: String,
    pub on_path: bool,
}

/// A skill row with child scripts.
#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct SkillRow {
    pub name: String,
    pub mode: AssignedMode,
    pub enabled: bool,
    pub scope: String,
    pub scripts: Vec<ScriptEntry>,
}

/// A simple row (hooks, mcp, permissions).
#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct SimpleRow {
    pub name: String,
    pub mode: AssignedMode,
    pub enabled: bool,
    pub scope: String,
}

/// A project entry managed in the Projects tab.
#[derive(Clone, Debug)]
pub struct ProjectEntry {
    pub path: PathBuf,
    pub alias: String,
}

// ---------------------------------------------------------------------------
// Flat cursor position for Skills tab
// ---------------------------------------------------------------------------

/// Position within the Skills tab (skill header or child script).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SkillPos {
    Skill(usize),
    Script(usize, usize), // (skill_idx, script_idx)
}

// ---------------------------------------------------------------------------
// Input mode
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum InputMode {
    Normal,
    AddProject,
    EditAlias,
    SelectProjects, // modal project picker
    DryRunning,
    Confirming,
    Deploying,
    Done,
}

// ---------------------------------------------------------------------------
// Deploy results (aggregated across passes)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
#[allow(dead_code)]
pub enum DeployStatus {
    Deployed,
    Skipped(String),
    Error(String),
}

/// A single item's aggregated result across all deploy passes.
#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct AggregatedResult {
    pub name: String,
    pub category: Category,
    pub status: DeployStatus,
    pub targets: Vec<String>, // "global", "project:web", etc.
    pub details: Vec<String>, // per-symlink lines
}

/// Aggregated deploy results across all passes. "Deployed" wins over "Skipped".
#[derive(Clone, Debug, Default)]
pub struct DeployResults {
    items: HashMap<String, AggregatedResult>,
    order: Vec<String>, // insertion order
}

impl DeployResults {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record a result. If status is Deployed and existing is Skipped, upgrade.
    pub fn record(
        &mut self,
        name: &str,
        category: Category,
        status: DeployStatus,
        target: &str,
        details: Vec<String>,
    ) {
        if let Some(existing) = self.items.get_mut(name) {
            // Deployed wins over Skipped
            if matches!(status, DeployStatus::Deployed)
                && matches!(existing.status, DeployStatus::Skipped(_))
            {
                existing.status = DeployStatus::Deployed;
            }
            // Error always wins
            if matches!(status, DeployStatus::Error(_)) {
                existing.status = status;
            }
            if !existing.targets.contains(&target.to_string()) {
                existing.targets.push(target.to_string());
            }
            existing.details.extend(details);
        } else {
            self.order.push(name.to_string());
            self.items.insert(
                name.to_string(),
                AggregatedResult {
                    name: name.to_string(),
                    category,
                    status,
                    targets: vec![target.to_string()],
                    details,
                },
            );
        }
    }

    pub fn deployed(&self) -> Vec<&AggregatedResult> {
        self.order
            .iter()
            .filter_map(|k| self.items.get(k))
            .filter(|r| matches!(r.status, DeployStatus::Deployed))
            .collect()
    }

    pub fn skipped(&self) -> Vec<&AggregatedResult> {
        self.order
            .iter()
            .filter_map(|k| self.items.get(k))
            .filter(|r| matches!(r.status, DeployStatus::Skipped(_)))
            .collect()
    }

    pub fn errors(&self) -> Vec<&AggregatedResult> {
        self.order
            .iter()
            .filter_map(|k| self.items.get(k))
            .filter(|r| matches!(r.status, DeployStatus::Error(_)))
            .collect()
    }

    pub fn clear(&mut self) {
        self.items.clear();
        self.order.clear();
    }
}

// ---------------------------------------------------------------------------
// Deploy plan
// ---------------------------------------------------------------------------

/// A structured deploy plan with multi-project support and per-script PATH.
#[derive(Clone, Debug)]
pub struct DeployPlan {
    pub global_items: Vec<String>,
    pub project_items: Vec<(PathBuf, Vec<String>)>, // (project_path, item_names)
    pub on_path_scripts: HashMap<String, HashSet<String>>,
}

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

pub struct App {
    // Tab state
    pub active_tab: usize,
    pub cursors: [usize; TAB_COUNT],

    // Per-tab data
    pub skill_rows: Vec<SkillRow>,
    pub hook_rows: Vec<SimpleRow>,
    pub mcp_rows: Vec<SimpleRow>,
    pub perm_rows: Vec<SimpleRow>,
    pub projects: Vec<ProjectEntry>,

    // Input state
    pub input_mode: InputMode,
    pub project_input: String,
    pub alias_input: String,

    // Modal state (SelectProjects)
    pub modal_cursor: usize,
    pub modal_selections: Vec<bool>,
    pub modal_item_name: String,
    pub modal_saved_mode: Option<AssignedMode>, // for cancel revert

    // Deploy state
    pub deploy_output: Vec<String>,
    pub deploy_results: DeployResults,
    pub deploy_plan: Option<DeployPlan>,
    pub scroll_offset: usize,

    // Shared
    pub should_quit: bool,
    pub repo_root: PathBuf,
    pub claude_config_dir: PathBuf,
}

impl App {
    /// Create a new App from discovery results.
    pub fn new(discover: DiscoverResult, repo_root: PathBuf, claude_config_dir: PathBuf) -> Self {
        let skill_rows: Vec<SkillRow> = discover
            .skills
            .iter()
            .map(|item| {
                let scripts = discover_scripts(&repo_root, &item.name);
                SkillRow {
                    name: item.name.clone(),
                    mode: if item.enabled {
                        AssignedMode::Global
                    } else {
                        AssignedMode::Skip
                    },
                    enabled: item.enabled,
                    scope: item.scope.clone(),
                    scripts,
                }
            })
            .collect();

        let hook_rows = make_simple_rows(&discover.hooks);
        let mcp_rows = make_simple_rows(&discover.mcp);
        let perm_rows = make_simple_rows(&discover.permissions);

        App {
            active_tab: TAB_SKILLS,
            cursors: [0; TAB_COUNT],
            skill_rows,
            hook_rows,
            mcp_rows,
            perm_rows,
            projects: Vec::new(),
            input_mode: InputMode::Normal,
            project_input: String::new(),
            alias_input: String::new(),
            modal_cursor: 0,
            modal_selections: Vec::new(),
            modal_item_name: String::new(),
            modal_saved_mode: None,
            deploy_output: Vec::new(),
            deploy_results: DeployResults::new(),
            deploy_plan: None,
            scroll_offset: 0,
            should_quit: false,
            repo_root,
            claude_config_dir,
        }
    }

    // -----------------------------------------------------------------------
    // Tab navigation
    // -----------------------------------------------------------------------

    pub fn next_tab(&mut self) {
        self.active_tab = (self.active_tab + 1) % TAB_COUNT;
    }

    pub fn prev_tab(&mut self) {
        self.active_tab = if self.active_tab == 0 {
            TAB_COUNT - 1
        } else {
            self.active_tab - 1
        };
    }

    // -----------------------------------------------------------------------
    // Cursor helpers
    // -----------------------------------------------------------------------

    fn cursor(&self) -> usize {
        self.cursors[self.active_tab]
    }

    fn set_cursor(&mut self, val: usize) {
        self.cursors[self.active_tab] = val;
    }

    /// Number of selectable rows in the current tab.
    fn row_count(&self) -> usize {
        match self.active_tab {
            TAB_SKILLS => self.skill_flat_len(),
            TAB_HOOKS => self.hook_rows.len(),
            TAB_MCP => self.mcp_rows.len(),
            TAB_PERMISSIONS => self.perm_rows.len(),
            TAB_PROJECTS => self.projects.len(),
            _ => 0,
        }
    }

    /// Move cursor up, skipping disabled items.
    pub fn move_up(&mut self) {
        let count = self.row_count();
        if count == 0 {
            return;
        }
        let start = self.cursor();
        let mut pos = start;
        loop {
            pos = if pos == 0 { count - 1 } else { pos - 1 };
            if pos == start {
                break;
            }
            if self.is_flat_selectable(pos) {
                self.set_cursor(pos);
                break;
            }
        }
    }

    /// Move cursor down, skipping disabled items.
    pub fn move_down(&mut self) {
        let count = self.row_count();
        if count == 0 {
            return;
        }
        let start = self.cursor();
        let mut pos = start;
        loop {
            pos = (pos + 1) % count;
            if pos == start {
                break;
            }
            if self.is_flat_selectable(pos) {
                self.set_cursor(pos);
                break;
            }
        }
    }

    fn is_flat_selectable(&self, idx: usize) -> bool {
        match self.active_tab {
            TAB_SKILLS => {
                if let Some(pos) = self.skill_flat_to_pos(idx) {
                    match pos {
                        SkillPos::Skill(si) => self.skill_rows[si].enabled,
                        SkillPos::Script(si, _) => {
                            self.skill_rows[si].enabled && self.skill_rows[si].mode.is_global()
                        }
                    }
                } else {
                    false
                }
            }
            TAB_HOOKS => self.hook_rows.get(idx).map(|r| r.enabled).unwrap_or(false),
            TAB_MCP => self.mcp_rows.get(idx).map(|r| r.enabled).unwrap_or(false),
            TAB_PERMISSIONS => self.perm_rows.get(idx).map(|r| r.enabled).unwrap_or(false),
            TAB_PROJECTS => true, // projects are always selectable
            _ => false,
        }
    }

    // -----------------------------------------------------------------------
    // Skills tab: flat index mapping
    // -----------------------------------------------------------------------

    /// Total number of flat rows in Skills tab (skill headers + scripts).
    pub fn skill_flat_len(&self) -> usize {
        self.skill_rows.iter().map(|s| 1 + s.scripts.len()).sum()
    }

    /// Map a flat index to (skill_idx, Optional script_idx).
    pub fn skill_flat_to_pos(&self, flat: usize) -> Option<SkillPos> {
        let mut idx = 0;
        for (si, skill) in self.skill_rows.iter().enumerate() {
            if idx == flat {
                return Some(SkillPos::Skill(si));
            }
            idx += 1;
            for sci in 0..skill.scripts.len() {
                if idx == flat {
                    return Some(SkillPos::Script(si, sci));
                }
                idx += 1;
            }
        }
        None
    }

    /// Map a SkillPos back to a flat index.
    #[allow(dead_code)]
    pub fn skill_pos_to_flat(&self, pos: &SkillPos) -> usize {
        let mut idx = 0;
        for (si, skill) in self.skill_rows.iter().enumerate() {
            match pos {
                SkillPos::Skill(target_si) if *target_si == si => return idx,
                SkillPos::Script(target_si, target_sci) if *target_si == si => {
                    return idx + 1 + target_sci;
                }
                _ => {}
            }
            idx += 1 + skill.scripts.len();
        }
        idx
    }

    /// Get the current SkillPos for the cursor (Skills tab only).
    pub fn current_skill_pos(&self) -> Option<SkillPos> {
        if self.active_tab == TAB_SKILLS {
            self.skill_flat_to_pos(self.cursor())
        } else {
            None
        }
    }

    // -----------------------------------------------------------------------
    // Target cycling
    // -----------------------------------------------------------------------

    /// Cycle current item's mode: Global -> Project -> Skip -> Global
    /// Hooks: Global -> Skip -> Global (no project support)
    /// Project mode remembers its previous selections when cycling away and back.
    pub fn cycle_target(&mut self) {
        match self.active_tab {
            TAB_SKILLS => {
                if let Some(SkillPos::Skill(si)) = self.current_skill_pos() {
                    let skill = &mut self.skill_rows[si];
                    if !skill.enabled {
                        return;
                    }
                    skill.mode = next_mode(&skill.mode, !self.projects.is_empty());
                    // Clear PATH when leaving Global
                    if !skill.mode.is_global() {
                        for script in &mut skill.scripts {
                            script.on_path = false;
                        }
                    }
                }
            }
            TAB_HOOKS => {
                let idx = self.cursor();
                if let Some(hook) = self.hook_rows.get_mut(idx) {
                    if !hook.enabled {
                        return;
                    }
                    // Hooks: only Global or Skip
                    hook.mode = match &hook.mode {
                        AssignedMode::Global => AssignedMode::Skip,
                        _ => AssignedMode::Global,
                    };
                }
            }
            TAB_MCP => {
                let idx = self.cursor();
                if let Some(row) = self.mcp_rows.get_mut(idx) {
                    if !row.enabled {
                        return;
                    }
                    row.mode = next_mode(&row.mode, !self.projects.is_empty());
                }
            }
            TAB_PERMISSIONS => {
                let idx = self.cursor();
                if let Some(row) = self.perm_rows.get_mut(idx) {
                    if !row.enabled {
                        return;
                    }
                    row.mode = next_mode(&row.mode, !self.projects.is_empty());
                }
            }
            _ => {}
        }
    }

    /// Toggle project assignment by project index (1-based number key).
    /// Note: UI now uses the project modal instead, but this is kept for tests.
    #[allow(dead_code)]
    pub fn toggle_project(&mut self, project_num: usize) {
        if project_num == 0 || project_num > self.projects.len() {
            return;
        }
        let alias = self.projects[project_num - 1].alias.clone();

        let mode = match self.active_tab {
            TAB_SKILLS => {
                if let Some(SkillPos::Skill(si)) = self.current_skill_pos() {
                    let skill = &mut self.skill_rows[si];
                    if !skill.enabled {
                        return;
                    }
                    Some(&mut skill.mode)
                } else {
                    None
                }
            }
            TAB_HOOKS => return, // hooks don't support projects
            TAB_MCP => {
                let idx = self.cursor();
                self.mcp_rows
                    .get_mut(idx)
                    .filter(|r| r.enabled)
                    .map(|r| &mut r.mode)
            }
            TAB_PERMISSIONS => {
                let idx = self.cursor();
                self.perm_rows
                    .get_mut(idx)
                    .filter(|r| r.enabled)
                    .map(|r| &mut r.mode)
            }
            _ => None,
        };

        if let Some(mode) = mode {
            match mode {
                AssignedMode::Project(ref mut aliases) => {
                    if let Some(pos) = aliases.iter().position(|a| *a == alias) {
                        aliases.remove(pos);
                        // If no projects left, revert to Skip
                        if aliases.is_empty() {
                            *mode = AssignedMode::Skip;
                        }
                    } else {
                        aliases.push(alias);
                    }
                }
                AssignedMode::Global | AssignedMode::Skip => {
                    // Switch to Project mode with this project
                    *mode = AssignedMode::Project(vec![alias]);
                }
            }

            // Clear PATH on skills when leaving Global
            if self.active_tab == TAB_SKILLS {
                if let Some(SkillPos::Skill(si)) = self.current_skill_pos() {
                    if !self.skill_rows[si].mode.is_global() {
                        for script in &mut self.skill_rows[si].scripts {
                            script.on_path = false;
                        }
                    }
                }
            }
        }
    }

    /// Toggle PATH for the script at cursor (Skills tab only).
    pub fn toggle_on_path(&mut self) {
        if self.active_tab != TAB_SKILLS {
            return;
        }
        if let Some(SkillPos::Script(si, sci)) = self.current_skill_pos() {
            let skill = &self.skill_rows[si];
            if skill.enabled && skill.mode.is_global() {
                self.skill_rows[si].scripts[sci].on_path =
                    !self.skill_rows[si].scripts[sci].on_path;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Project selector modal
    // -----------------------------------------------------------------------

    /// Get the current item's mode by name (across all tabs).
    fn get_item_mode(&self, name: &str) -> Option<&AssignedMode> {
        self.skill_rows
            .iter()
            .find(|s| s.name == name)
            .map(|s| &s.mode)
            .or_else(|| {
                self.hook_rows
                    .iter()
                    .find(|h| h.name == name)
                    .map(|h| &h.mode)
            })
            .or_else(|| {
                self.mcp_rows
                    .iter()
                    .find(|m| m.name == name)
                    .map(|m| &m.mode)
            })
            .or_else(|| {
                self.perm_rows
                    .iter()
                    .find(|p| p.name == name)
                    .map(|p| &p.mode)
            })
    }

    /// Open the project selector modal for the given item.
    pub fn open_project_modal(&mut self, item_name: &str) {
        if self.projects.is_empty() {
            return;
        }
        let current_mode = self.get_item_mode(item_name).cloned();
        self.open_project_modal_with_saved(item_name, current_mode.unwrap_or(AssignedMode::Skip));
    }

    /// Open the modal with an explicit saved mode (for cancel revert).
    /// Used by cycle_target to save the pre-cycle mode.
    fn open_project_modal_with_saved(&mut self, item_name: &str, saved_mode: AssignedMode) {
        if self.projects.is_empty() {
            return;
        }
        self.modal_saved_mode = Some(saved_mode);
        self.modal_item_name = item_name.to_string();
        self.modal_cursor = 0;

        // Populate selections from current Project aliases
        let current_aliases: Vec<String> = match self.get_item_mode(item_name) {
            Some(AssignedMode::Project(aliases)) => aliases.clone(),
            _ => Vec::new(),
        };
        self.modal_selections = self
            .projects
            .iter()
            .map(|p| current_aliases.contains(&p.alias))
            .collect();

        self.input_mode = InputMode::SelectProjects;
    }

    /// Confirm the project modal — apply selections back to item.
    pub fn confirm_project_modal(&mut self) {
        let selected_aliases: Vec<String> = self
            .projects
            .iter()
            .zip(self.modal_selections.iter())
            .filter(|(_, &selected)| selected)
            .map(|(p, _)| p.alias.clone())
            .collect();

        let new_mode = if selected_aliases.is_empty() {
            AssignedMode::Skip
        } else {
            AssignedMode::Project(selected_aliases)
        };

        self.apply_mode_to_item(&self.modal_item_name.clone(), new_mode);
        self.input_mode = InputMode::Normal;
        self.modal_saved_mode = None;
    }

    /// Cancel the project modal — revert to saved mode.
    pub fn cancel_project_modal(&mut self) {
        if let Some(saved) = self.modal_saved_mode.take() {
            self.apply_mode_to_item(&self.modal_item_name.clone(), saved);
        }
        self.input_mode = InputMode::Normal;
    }

    /// Apply a mode to an item by name.
    fn apply_mode_to_item(&mut self, name: &str, mode: AssignedMode) {
        if let Some(skill) = self.skill_rows.iter_mut().find(|s| s.name == name) {
            skill.mode = mode;
            if !skill.mode.is_global() {
                for script in &mut skill.scripts {
                    script.on_path = false;
                }
            }
            return;
        }
        if let Some(row) = self.mcp_rows.iter_mut().find(|m| m.name == name) {
            row.mode = mode;
            return;
        }
        if let Some(row) = self.perm_rows.iter_mut().find(|p| p.name == name) {
            row.mode = mode;
        }
    }

    /// Get the name of the currently selected item (for opening modal with P key).
    pub fn current_item_name(&self) -> Option<String> {
        match self.active_tab {
            TAB_SKILLS => {
                if let Some(SkillPos::Skill(si)) = self.current_skill_pos() {
                    Some(self.skill_rows[si].name.clone())
                } else {
                    None
                }
            }
            TAB_HOOKS => {
                let idx = self.cursor();
                self.hook_rows.get(idx).map(|r| r.name.clone())
            }
            TAB_MCP => {
                let idx = self.cursor();
                self.mcp_rows.get(idx).map(|r| r.name.clone())
            }
            TAB_PERMISSIONS => {
                let idx = self.cursor();
                self.perm_rows.get(idx).map(|r| r.name.clone())
            }
            _ => None,
        }
    }

    // -----------------------------------------------------------------------
    // Bulk operations
    // -----------------------------------------------------------------------

    /// Set all enabled items across all tabs to Global.
    pub fn all_global(&mut self) {
        for skill in &mut self.skill_rows {
            if skill.enabled {
                skill.mode = AssignedMode::Global;
            }
        }
        for hook in &mut self.hook_rows {
            if hook.enabled {
                hook.mode = AssignedMode::Global;
            }
        }
        for mcp in &mut self.mcp_rows {
            if mcp.enabled {
                mcp.mode = AssignedMode::Global;
            }
        }
        for perm in &mut self.perm_rows {
            if perm.enabled {
                perm.mode = AssignedMode::Global;
            }
        }
    }

    /// Set all enabled items across all tabs to Skip.
    pub fn skip_all(&mut self) {
        for skill in &mut self.skill_rows {
            if skill.enabled {
                skill.mode = AssignedMode::Skip;
                for script in &mut skill.scripts {
                    script.on_path = false;
                }
            }
        }
        for hook in &mut self.hook_rows {
            if hook.enabled {
                hook.mode = AssignedMode::Skip;
            }
        }
        for mcp in &mut self.mcp_rows {
            if mcp.enabled {
                mcp.mode = AssignedMode::Skip;
            }
        }
        for perm in &mut self.perm_rows {
            if perm.enabled {
                perm.mode = AssignedMode::Skip;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Project management
    // -----------------------------------------------------------------------

    pub fn start_add_project(&mut self) {
        self.input_mode = InputMode::AddProject;
        self.project_input.clear();
    }

    /// Confirm the project path input. Returns true if valid and added.
    pub fn confirm_add_project(&mut self) -> bool {
        let path = expand_tilde(self.project_input.trim());
        if path.is_dir() {
            let canonical = path.canonicalize().unwrap_or(path.clone());
            // Avoid duplicates
            if self.projects.iter().any(|p| p.path == canonical) {
                self.input_mode = InputMode::Normal;
                self.project_input.clear();
                return false;
            }
            let alias = canonical
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "project".to_string());
            // Ensure unique alias
            let alias = unique_alias(&alias, &self.projects);
            self.projects.push(ProjectEntry {
                path: canonical,
                alias,
            });
            self.input_mode = InputMode::Normal;
            self.project_input.clear();
            true
        } else {
            false
        }
    }

    pub fn cancel_add_project(&mut self) {
        self.input_mode = InputMode::Normal;
        self.project_input.clear();
    }

    /// Start editing the alias of the selected project.
    pub fn start_edit_alias(&mut self) {
        if self.active_tab != TAB_PROJECTS {
            return;
        }
        let idx = self.cursor();
        if let Some(proj) = self.projects.get(idx) {
            self.alias_input = proj.alias.clone();
            self.input_mode = InputMode::EditAlias;
        }
    }

    /// Confirm editing the alias.
    pub fn confirm_edit_alias(&mut self) -> bool {
        let idx = self.cursor();
        let new_alias = self.alias_input.trim().to_string();
        if new_alias.is_empty() {
            return false;
        }
        // Check uniqueness (excluding current)
        let is_unique = !self
            .projects
            .iter()
            .enumerate()
            .any(|(i, p)| i != idx && p.alias == new_alias);
        if !is_unique {
            return false;
        }
        if let Some(proj) = self.projects.get_mut(idx) {
            let old_alias = proj.alias.clone();
            proj.alias = new_alias.clone();
            // Update all references
            self.rename_project_alias(&old_alias, &new_alias);
        }
        self.input_mode = InputMode::Normal;
        self.alias_input.clear();
        true
    }

    pub fn cancel_edit_alias(&mut self) {
        self.input_mode = InputMode::Normal;
        self.alias_input.clear();
    }

    /// Delete the selected project and remove it from all assignments.
    pub fn delete_project(&mut self) {
        if self.active_tab != TAB_PROJECTS {
            return;
        }
        let idx = self.cursor();
        if idx >= self.projects.len() {
            return;
        }
        let alias = self.projects[idx].alias.clone();
        self.projects.remove(idx);
        self.remove_project_alias(&alias);

        // Fix cursor
        if !self.projects.is_empty() && self.cursor() >= self.projects.len() {
            self.set_cursor(self.projects.len() - 1);
        }
    }

    fn rename_project_alias(&mut self, old: &str, new: &str) {
        for skill in &mut self.skill_rows {
            if let AssignedMode::Project(ref mut aliases) = skill.mode {
                for a in aliases.iter_mut() {
                    if a == old {
                        *a = new.to_string();
                    }
                }
            }
        }
        for row in &mut self.mcp_rows {
            if let AssignedMode::Project(ref mut aliases) = row.mode {
                for a in aliases.iter_mut() {
                    if a == old {
                        *a = new.to_string();
                    }
                }
            }
        }
        for row in &mut self.perm_rows {
            if let AssignedMode::Project(ref mut aliases) = row.mode {
                for a in aliases.iter_mut() {
                    if a == old {
                        *a = new.to_string();
                    }
                }
            }
        }
    }

    fn remove_project_alias(&mut self, alias: &str) {
        let remove_from = |mode: &mut AssignedMode| {
            if let AssignedMode::Project(ref mut aliases) = mode {
                aliases.retain(|a| a != alias);
                if aliases.is_empty() {
                    *mode = AssignedMode::Skip;
                }
            }
        };
        for skill in &mut self.skill_rows {
            remove_from(&mut skill.mode);
            if !skill.mode.is_global() {
                for script in &mut skill.scripts {
                    script.on_path = false;
                }
            }
        }
        for row in &mut self.mcp_rows {
            remove_from(&mut row.mode);
        }
        for row in &mut self.perm_rows {
            remove_from(&mut row.mode);
        }
    }

    /// Resolve a project alias to its path.
    pub fn project_path_for_alias(&self, alias: &str) -> Option<PathBuf> {
        self.projects
            .iter()
            .find(|p| p.alias == alias)
            .map(|p| p.path.clone())
    }

    // -----------------------------------------------------------------------
    // Deploy plan
    // -----------------------------------------------------------------------

    /// Build a structured deploy plan from current state.
    pub fn build_deploy_plan(&self) -> DeployPlan {
        let mut global_items = Vec::new();
        let mut project_map: HashMap<PathBuf, Vec<String>> = HashMap::new();
        let mut on_path_scripts: HashMap<String, HashSet<String>> = HashMap::new();

        // Collect items from all tabs
        let all_items: Vec<(&str, &AssignedMode)> = self
            .skill_rows
            .iter()
            .filter(|s| s.enabled)
            .map(|s| (s.name.as_str(), &s.mode))
            .chain(
                self.hook_rows
                    .iter()
                    .filter(|h| h.enabled)
                    .map(|h| (h.name.as_str(), &h.mode)),
            )
            .chain(
                self.mcp_rows
                    .iter()
                    .filter(|m| m.enabled)
                    .map(|m| (m.name.as_str(), &m.mode)),
            )
            .chain(
                self.perm_rows
                    .iter()
                    .filter(|p| p.enabled)
                    .map(|p| (p.name.as_str(), &p.mode)),
            )
            .collect();

        for (name, mode) in all_items {
            match mode {
                AssignedMode::Global => {
                    global_items.push(name.to_string());
                }
                AssignedMode::Project(aliases) => {
                    for alias in aliases {
                        if let Some(path) = self.project_path_for_alias(alias) {
                            project_map.entry(path).or_default().push(name.to_string());
                        }
                    }
                }
                AssignedMode::Skip => {}
            }
        }

        // Collect per-script PATH
        for skill in &self.skill_rows {
            if !skill.enabled || !skill.mode.is_global() {
                continue;
            }
            let path_scripts: HashSet<String> = skill
                .scripts
                .iter()
                .filter(|s| s.on_path)
                .map(|s| s.name.clone())
                .collect();
            if !path_scripts.is_empty() {
                on_path_scripts.insert(skill.name.clone(), path_scripts);
            }
        }

        // Sort project items for deterministic ordering
        let mut project_items: Vec<(PathBuf, Vec<String>)> = project_map.into_iter().collect();
        project_items.sort_by(|a, b| a.0.cmp(&b.0));

        DeployPlan {
            global_items,
            project_items,
            on_path_scripts,
        }
    }

    // -----------------------------------------------------------------------
    // Deploy mode transitions
    // -----------------------------------------------------------------------

    pub fn start_dry_run(&mut self, plan: DeployPlan) {
        self.input_mode = InputMode::DryRunning;
        self.deploy_output.clear();
        self.deploy_results.clear();
        self.deploy_plan = Some(plan);
        self.scroll_offset = 0;
    }

    pub fn finish_dry_run(&mut self) {
        self.input_mode = InputMode::Confirming;
        self.scroll_offset = 0;
    }

    pub fn start_deploy(&mut self) {
        self.input_mode = InputMode::Deploying;
        self.deploy_output.clear();
        self.deploy_results.clear();
        self.scroll_offset = 0;
    }

    pub fn finish_deploy(&mut self) {
        self.input_mode = InputMode::Done;
    }

    pub fn cancel_deploy(&mut self) {
        self.input_mode = InputMode::Normal;
        self.deploy_output.clear();
        self.deploy_results.clear();
        self.deploy_plan = None;
        self.scroll_offset = 0;
    }

    // -----------------------------------------------------------------------
    // Scroll
    // -----------------------------------------------------------------------

    pub fn scroll_up(&mut self, n: usize) {
        let max_offset = self.deploy_output.len().saturating_sub(1);
        self.scroll_offset = (self.scroll_offset + n).min(max_offset);
    }

    pub fn scroll_down(&mut self, n: usize) {
        self.scroll_offset = self.scroll_offset.saturating_sub(n);
    }

    pub fn scroll_to_top(&mut self) {
        self.scroll_offset = self.deploy_output.len().saturating_sub(1);
    }

    pub fn scroll_to_bottom(&mut self) {
        self.scroll_offset = 0;
    }

    // -----------------------------------------------------------------------
    // Summary helpers
    // -----------------------------------------------------------------------

    /// Count of items by mode (for header summary).
    #[allow(dead_code)]
    pub fn target_counts(&self) -> Vec<(String, usize)> {
        let mut counts: Vec<(String, usize)> = Vec::new();
        let all_modes: Vec<&AssignedMode> = self
            .skill_rows
            .iter()
            .filter(|s| s.enabled)
            .map(|s| &s.mode)
            .chain(self.hook_rows.iter().filter(|h| h.enabled).map(|h| &h.mode))
            .chain(self.mcp_rows.iter().filter(|m| m.enabled).map(|m| &m.mode))
            .chain(self.perm_rows.iter().filter(|p| p.enabled).map(|p| &p.mode))
            .collect();

        for mode in all_modes {
            let label = mode.badge();
            if let Some(entry) = counts.iter_mut().find(|(l, _)| *l == label) {
                entry.1 += 1;
            } else {
                counts.push((label, 1));
            }
        }
        counts
    }

    /// Check if the deploy plan is empty (nothing to do).
    #[allow(dead_code)]
    pub fn plan_is_empty(&self) -> bool {
        if let Some(ref plan) = self.deploy_plan {
            plan.global_items.is_empty() && plan.project_items.is_empty()
        } else {
            true
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Discover scripts in skills/<name>/bin/
fn discover_scripts(repo_root: &PathBuf, skill_name: &str) -> Vec<ScriptEntry> {
    let bin_dir = repo_root.join("skills").join(skill_name).join("bin");
    if !bin_dir.is_dir() {
        return Vec::new();
    }
    let mut scripts = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&bin_dir) {
        let mut entries: Vec<_> = entries.filter_map(|e| e.ok()).collect();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            if entry.path().is_file() {
                scripts.push(ScriptEntry {
                    name: entry.file_name().to_string_lossy().to_string(),
                    on_path: false,
                });
            }
        }
    }
    scripts
}

fn make_simple_rows(items: &[DiscoveredItem]) -> Vec<SimpleRow> {
    items
        .iter()
        .map(|item| SimpleRow {
            name: item.name.clone(),
            mode: if item.enabled {
                AssignedMode::Global
            } else {
                AssignedMode::Skip
            },
            enabled: item.enabled,
            scope: item.scope.clone(),
        })
        .collect()
}

/// Cycle mode: Global -> Project([]) -> Skip -> Global
/// If no projects available, skip the Project step.
fn next_mode(current: &AssignedMode, has_projects: bool) -> AssignedMode {
    match current {
        AssignedMode::Global => {
            if has_projects {
                AssignedMode::Project(Vec::new())
            } else {
                AssignedMode::Skip
            }
        }
        AssignedMode::Project(_) => AssignedMode::Skip,
        AssignedMode::Skip => AssignedMode::Global,
    }
}

/// Generate a unique alias by appending -2, -3, etc. if needed.
fn unique_alias(base: &str, projects: &[ProjectEntry]) -> String {
    if !projects.iter().any(|p| p.alias == base) {
        return base.to_string();
    }
    let mut n = 2;
    loop {
        let candidate = format!("{}-{}", base, n);
        if !projects.iter().any(|p| p.alias == candidate) {
            return candidate;
        }
        n += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::discovery::DiscoverResult;

    fn make_discover_result(
        skills: &[(&str, bool)],
        hooks: &[(&str, bool)],
        mcp: &[(&str, bool)],
        perms: &[(&str, bool)],
    ) -> DiscoverResult {
        let make_items = |items: &[(&str, bool)]| -> Vec<DiscoveredItem> {
            items
                .iter()
                .map(|(name, enabled)| DiscoveredItem {
                    name: name.to_string(),
                    enabled: *enabled,
                    scope: "global".to_string(),
                    on_path: None,
                })
                .collect()
        };

        DiscoverResult {
            repo_root: "/tmp/test".to_string(),
            profiles: vec![],
            skills: make_items(skills),
            hooks: make_items(hooks),
            mcp: make_items(mcp),
            permissions: make_items(perms),
        }
    }

    // Note: tests that rely on disk (discover_scripts) need a temp dir
    // or pass an empty skill list. Tests here cover logic only.

    fn make_app(
        skills: &[(&str, bool)],
        hooks: &[(&str, bool)],
        mcp: &[(&str, bool)],
        perms: &[(&str, bool)],
    ) -> App {
        let discover = make_discover_result(skills, hooks, mcp, perms);
        // Use /tmp which exists but has no skills/*/bin/ so scripts will be empty
        App::new(
            discover,
            PathBuf::from("/tmp"),
            PathBuf::from("/tmp/.claude"),
        )
    }

    #[test]
    fn test_new_populates_from_discover() {
        let app = make_app(
            &[("catchup", true), ("jar-explore", true)],
            &[("bash-safety", true)],
            &[],
            &[("git", true)],
        );

        assert_eq!(app.skill_rows.len(), 2);
        assert_eq!(app.skill_rows[0].name, "catchup");
        assert_eq!(app.hook_rows.len(), 1);
        assert_eq!(app.hook_rows[0].name, "bash-safety");
        assert_eq!(app.perm_rows.len(), 1);
        assert_eq!(app.perm_rows[0].name, "git");
    }

    #[test]
    fn test_tab_switching() {
        let mut app = make_app(&[("a", true)], &[("b", true)], &[], &[]);

        assert_eq!(app.active_tab, TAB_SKILLS);
        app.next_tab();
        assert_eq!(app.active_tab, TAB_HOOKS);
        app.next_tab();
        assert_eq!(app.active_tab, TAB_MCP);
        app.prev_tab();
        assert_eq!(app.active_tab, TAB_HOOKS);

        // Wrap around
        app.active_tab = TAB_PROJECTS;
        app.next_tab();
        assert_eq!(app.active_tab, TAB_SKILLS);

        app.prev_tab();
        assert_eq!(app.active_tab, TAB_PROJECTS);
    }

    #[test]
    fn test_cycle_target_global_skip() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);

        // Default is Global
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);

        // No projects: Global -> Skip -> Global
        app.cycle_target();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);

        app.cycle_target();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);
    }

    #[test]
    fn test_cycle_target_with_projects() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/proj-a"),
            alias: "proj-a".to_string(),
        });

        // Global -> Project([]) -> Skip -> Global (no auto-modal)
        app.cycle_target();
        assert!(matches!(&app.skill_rows[0].mode, AssignedMode::Project(a) if a.is_empty()));
        assert_eq!(app.input_mode, InputMode::Normal); // no modal opened

        app.cycle_target();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);

        app.cycle_target();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);
    }

    #[test]
    fn test_project_modal_from_p_key() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/api"),
            alias: "api".to_string(),
        });

        // Open modal via P key (from Global mode)
        app.open_project_modal("a");
        assert_eq!(app.input_mode, InputMode::SelectProjects);

        // Select first project and confirm -> sets to Project mode
        app.modal_selections[0] = true;
        app.confirm_project_modal();
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["web".to_string()])
        );
        assert_eq!(app.input_mode, InputMode::Normal);
    }

    #[test]
    fn test_project_modal_cancel_reverts() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });

        // Start from Global, open modal, cancel -> stays Global
        app.open_project_modal("a");
        app.cancel_project_modal();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);
        assert_eq!(app.input_mode, InputMode::Normal);
    }

    #[test]
    fn test_project_modal_empty_confirm_goes_to_skip() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });

        // Open modal, confirm with nothing selected -> Skip
        app.open_project_modal("a");
        app.confirm_project_modal();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);
    }

    #[test]
    fn test_project_mode_remembers_selections() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });

        // Set to Project with "web"
        app.open_project_modal("a");
        app.modal_selections[0] = true;
        app.confirm_project_modal();
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["web".to_string()])
        );

        // Cycle away to Skip, then back to Global
        app.cycle_target(); // Project -> Skip
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);
        app.cycle_target(); // Skip -> Global
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Global);

        // Cycle to Project again — selections are empty (fresh cycle)
        app.cycle_target(); // Global -> Project([])
        assert!(matches!(&app.skill_rows[0].mode, AssignedMode::Project(a) if a.is_empty()));
    }

    #[test]
    fn test_deploy_results_aggregator() {
        let mut results = DeployResults::new();

        // First pass: item deployed globally
        results.record(
            "session",
            Category::Skills,
            DeployStatus::Deployed,
            "global",
            vec![],
        );
        // Second pass: same item skipped in project pass
        results.record(
            "session",
            Category::Skills,
            DeployStatus::Skipped("filtered out".to_string()),
            "project:web",
            vec![],
        );

        // Deployed should win
        assert_eq!(results.deployed().len(), 1);
        assert_eq!(results.skipped().len(), 0);
        assert_eq!(results.deployed()[0].targets.len(), 2);
    }

    #[test]
    fn test_deploy_results_skipped_upgrades_to_deployed() {
        let mut results = DeployResults::new();

        // First pass: skipped globally
        results.record(
            "jar",
            Category::Skills,
            DeployStatus::Skipped("filtered out".to_string()),
            "global",
            vec![],
        );
        // Second pass: deployed in project
        results.record(
            "jar",
            Category::Skills,
            DeployStatus::Deployed,
            "project:web",
            vec![],
        );

        assert_eq!(results.deployed().len(), 1);
        assert_eq!(results.skipped().len(), 0);
    }

    #[test]
    fn test_hooks_only_global_or_skip() {
        let mut app = make_app(&[], &[("my-hook", true)], &[], &[]);
        app.active_tab = TAB_HOOKS;
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/proj-a"),
            alias: "proj-a".to_string(),
        });

        assert_eq!(app.hook_rows[0].mode, AssignedMode::Global);

        app.cycle_target();
        assert_eq!(app.hook_rows[0].mode, AssignedMode::Skip);

        app.cycle_target();
        assert_eq!(app.hook_rows[0].mode, AssignedMode::Global);
    }

    #[test]
    fn test_toggle_project() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/api"),
            alias: "api".to_string(),
        });

        // Toggle project 1
        app.toggle_project(1);
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["web".to_string()])
        );

        // Toggle project 2
        app.toggle_project(2);
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["web".to_string(), "api".to_string()])
        );

        // Un-toggle project 1
        app.toggle_project(1);
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["api".to_string()])
        );

        // Un-toggle project 2 -> reverts to Skip
        app.toggle_project(2);
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);
    }

    #[test]
    fn test_all_global() {
        let mut app = make_app(&[("a", true), ("b", true)], &[("c", true)], &[], &[]);

        app.skip_all();
        assert!(app.skill_rows.iter().all(|s| s.mode == AssignedMode::Skip));
        assert!(app.hook_rows.iter().all(|h| h.mode == AssignedMode::Skip));

        app.all_global();
        assert!(app
            .skill_rows
            .iter()
            .all(|s| s.mode == AssignedMode::Global));
        assert!(app.hook_rows.iter().all(|h| h.mode == AssignedMode::Global));
    }

    #[test]
    fn test_add_project() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);

        assert!(app.projects.is_empty());

        app.start_add_project();
        assert_eq!(app.input_mode, InputMode::AddProject);

        // Use /tmp which exists
        app.project_input = "/tmp".to_string();
        let ok = app.confirm_add_project();
        assert!(ok);
        assert_eq!(app.input_mode, InputMode::Normal);
        assert_eq!(app.projects.len(), 1);
    }

    #[test]
    fn test_cancel_add_project() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.start_add_project();
        app.project_input = "some-text".to_string();
        app.cancel_add_project();

        assert_eq!(app.input_mode, InputMode::Normal);
        assert!(app.project_input.is_empty());
    }

    #[test]
    fn test_delete_project_removes_assignments() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/web"),
            alias: "web".to_string(),
        });

        // Assign skill to this project
        app.toggle_project(1);
        assert_eq!(
            app.skill_rows[0].mode,
            AssignedMode::Project(vec!["web".to_string()])
        );

        // Delete project
        app.active_tab = TAB_PROJECTS;
        app.cursors[TAB_PROJECTS] = 0;
        app.delete_project();

        assert!(app.projects.is_empty());
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip); // reverted
    }

    #[test]
    fn test_build_deploy_plan() {
        let mut app = make_app(&[("a", true), ("b", true), ("c", true)], &[], &[], &[]);
        app.projects.push(ProjectEntry {
            path: PathBuf::from("/work/proj"),
            alias: "proj".to_string(),
        });

        // b -> project "proj"
        app.cursors[TAB_SKILLS] = 1; // flat index 1 = skill "b" (no scripts)
        app.toggle_project(1);

        // c -> skip
        app.cursors[TAB_SKILLS] = 2;
        app.cycle_target(); // Global -> Project([])
        app.cycle_target(); // Project -> Skip

        let plan = app.build_deploy_plan();
        assert!(plan.global_items.contains(&"a".to_string()));
        assert!(!plan.global_items.contains(&"b".to_string()));
        assert!(!plan.global_items.contains(&"c".to_string()));
        assert_eq!(plan.project_items.len(), 1);
        assert_eq!(plan.project_items[0].0, PathBuf::from("/work/proj"));
        assert!(plan.project_items[0].1.contains(&"b".to_string()));
    }

    #[test]
    fn test_on_path_clears_on_mode_change() {
        let mut app = make_app(&[("a", true)], &[], &[], &[]);
        // Manually add a script since we can't discover from /tmp
        app.skill_rows[0].scripts.push(ScriptEntry {
            name: "my-script".to_string(),
            on_path: true,
        });

        assert!(app.skill_rows[0].scripts[0].on_path);

        // Switch to Skip
        app.cycle_target();
        assert_eq!(app.skill_rows[0].mode, AssignedMode::Skip);
        assert!(!app.skill_rows[0].scripts[0].on_path); // cleared
    }

    #[test]
    fn test_skill_flat_mapping() {
        let mut app = make_app(&[("a", true), ("b", true)], &[], &[], &[]);
        // Add scripts manually
        app.skill_rows[0].scripts = vec![
            ScriptEntry {
                name: "s1".to_string(),
                on_path: false,
            },
            ScriptEntry {
                name: "s2".to_string(),
                on_path: false,
            },
        ];
        app.skill_rows[1].scripts = vec![ScriptEntry {
            name: "s3".to_string(),
            on_path: false,
        }];

        // Flat: 0=a, 1=s1, 2=s2, 3=b, 4=s3
        assert_eq!(app.skill_flat_len(), 5);
        assert_eq!(app.skill_flat_to_pos(0), Some(SkillPos::Skill(0)));
        assert_eq!(app.skill_flat_to_pos(1), Some(SkillPos::Script(0, 0)));
        assert_eq!(app.skill_flat_to_pos(2), Some(SkillPos::Script(0, 1)));
        assert_eq!(app.skill_flat_to_pos(3), Some(SkillPos::Skill(1)));
        assert_eq!(app.skill_flat_to_pos(4), Some(SkillPos::Script(1, 0)));
        assert_eq!(app.skill_flat_to_pos(5), None);

        // Reverse mapping
        assert_eq!(app.skill_pos_to_flat(&SkillPos::Skill(0)), 0);
        assert_eq!(app.skill_pos_to_flat(&SkillPos::Script(0, 1)), 2);
        assert_eq!(app.skill_pos_to_flat(&SkillPos::Skill(1)), 3);
    }

    #[test]
    fn test_badge_display() {
        assert_eq!(AssignedMode::Global.badge(), "GLOBAL");
        assert_eq!(AssignedMode::Skip.badge(), "SKIP");
        // All Project modes show "PROJECT" in badge
        assert_eq!(
            AssignedMode::Project(vec!["web".to_string()]).badge(),
            "PROJECT"
        );
        assert_eq!(AssignedMode::Project(vec![]).badge(), "PROJECT");
    }

    #[test]
    fn test_project_label() {
        assert_eq!(AssignedMode::Global.project_label(), None);
        assert_eq!(AssignedMode::Skip.project_label(), None);
        assert_eq!(AssignedMode::Project(vec![]).project_label(), None);
        assert_eq!(
            AssignedMode::Project(vec!["web".to_string()]).project_label(),
            Some("web".to_string())
        );
        assert_eq!(
            AssignedMode::Project(vec!["web".to_string(), "api".to_string()]).project_label(),
            Some("web, api".to_string())
        );
    }

    #[test]
    fn test_unique_alias() {
        let projects = vec![ProjectEntry {
            path: PathBuf::from("/a"),
            alias: "web".to_string(),
        }];
        assert_eq!(unique_alias("api", &projects), "api");
        assert_eq!(unique_alias("web", &projects), "web-2");
    }
}
