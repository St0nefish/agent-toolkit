// tui/events.rs - Crossterm event loop and terminal management

use super::app::{
    expand_tilde, App, AssignedMode, Category, DeployResults, DeployStatus, InputMode, TAB_HOOKS,
    TAB_PROJECTS,
};
use super::state;
use super::ui;
use crate::cli::{execute_deploy, DeployContext};
use crate::discovery::discover_items;
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Write};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

/// Run the interactive TUI.
pub fn run_tui(repo_root: PathBuf, claude_config_dir: PathBuf) -> Result<()> {
    // Discover items
    let empty_profile = Value::Object(Default::default());
    let discover_result = discover_items(&repo_root, &empty_profile);

    // Initialize app
    let mut app = App::new(discover_result, repo_root.clone(), claude_config_dir);

    // Load persistent state
    if let Some(saved_state) = state::load_state(&repo_root) {
        state::apply_state(&mut app, &saved_state);
    }

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Event loop
    let result = run_event_loop(&mut terminal, &mut app);

    // Save state on exit
    let tui_state = state::capture_state(&app);
    let _ = state::save_state(&repo_root, &tui_state);

    // Restore terminal
    disable_raw_mode()?;
    crossterm::execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run_event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    loop {
        terminal.draw(|f| ui::draw(f, app))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press {
                continue;
            }

            match app.input_mode {
                InputMode::Normal => handle_normal_input(terminal, app, key.code)?,
                InputMode::AddProject => handle_add_project_input(app, key.code),
                InputMode::EditAlias => handle_edit_alias_input(app, key.code),
                InputMode::SelectProjects => handle_select_projects_input(app, key.code),
                InputMode::Confirming => handle_confirming_input(terminal, app, key.code)?,
                InputMode::Done => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => {
                        app.should_quit = true;
                    }
                    KeyCode::Up | KeyCode::Char('k') => app.scroll_up(1),
                    KeyCode::Down | KeyCode::Char('j') => app.scroll_down(1),
                    KeyCode::PageUp => app.scroll_up(20),
                    KeyCode::PageDown => app.scroll_down(20),
                    KeyCode::Home | KeyCode::Char('g') => app.scroll_to_top(),
                    KeyCode::End | KeyCode::Char('G') => app.scroll_to_bottom(),
                    _ => {}
                },
                InputMode::DryRunning | InputMode::Deploying => {
                    // No input during deploy
                }
            }
        }

        if app.should_quit {
            break;
        }
    }

    Ok(())
}

fn handle_normal_input(
    _terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    code: KeyCode,
) -> Result<()> {
    match code {
        KeyCode::Char('q') | KeyCode::Esc => {
            app.should_quit = true;
        }
        // Tab switching
        KeyCode::Tab => app.next_tab(),
        KeyCode::BackTab => app.prev_tab(),
        // Navigation
        KeyCode::Up | KeyCode::Char('k') => app.move_up(),
        KeyCode::Down | KeyCode::Char('j') => app.move_down(),
        // Target cycling
        KeyCode::Char(' ') => {
            app.cycle_target();
        }
        // Bulk operations
        KeyCode::Char('a') => {
            if app.active_tab == TAB_PROJECTS {
                app.start_add_project();
            } else {
                app.all_global();
            }
        }
        KeyCode::Char('s') => app.skip_all(),
        // PATH toggle (Skills tab, script rows only)
        KeyCode::Char('o') | KeyCode::Char('O') => app.toggle_on_path(),
        // Project selector modal (P key)
        KeyCode::Char('p') | KeyCode::Char('P') => {
            if app.active_tab != TAB_PROJECTS
                && app.active_tab != TAB_HOOKS
                && !app.projects.is_empty()
            {
                if let Some(name) = app.current_item_name() {
                    app.open_project_modal(&name);
                }
            }
        }
        // Projects tab actions
        KeyCode::Char('d') | KeyCode::Char('D') => {
            if app.active_tab == TAB_PROJECTS {
                app.delete_project();
            }
        }
        KeyCode::Char('e') | KeyCode::Char('E') => {
            if app.active_tab == TAB_PROJECTS {
                app.start_edit_alias();
            }
        }
        // Deploy
        KeyCode::Enter => {
            let plan = app.build_deploy_plan();
            if !plan.global_items.is_empty() || !plan.project_items.is_empty() {
                app.start_dry_run(plan);
                build_preview(app);
                app.finish_dry_run();
            }
        }
        _ => {}
    }
    Ok(())
}

fn handle_add_project_input(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Enter => {
            app.confirm_add_project();
        }
        KeyCode::Esc => app.cancel_add_project(),
        KeyCode::Char(c) => app.project_input.push(c),
        KeyCode::Backspace => {
            app.project_input.pop();
        }
        KeyCode::Tab => {
            tab_complete_path(&mut app.project_input);
        }
        _ => {}
    }
}

fn handle_edit_alias_input(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Enter => {
            app.confirm_edit_alias();
        }
        KeyCode::Esc => app.cancel_edit_alias(),
        KeyCode::Char(c) => app.alias_input.push(c),
        KeyCode::Backspace => {
            app.alias_input.pop();
        }
        _ => {}
    }
}

fn handle_select_projects_input(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Up | KeyCode::Char('k') => {
            if app.modal_cursor > 0 {
                app.modal_cursor -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.modal_cursor + 1 < app.modal_selections.len() {
                app.modal_cursor += 1;
            }
        }
        KeyCode::Char(' ') => {
            if app.modal_cursor < app.modal_selections.len() {
                app.modal_selections[app.modal_cursor] = !app.modal_selections[app.modal_cursor];
            }
        }
        KeyCode::Enter => {
            app.confirm_project_modal();
        }
        KeyCode::Esc => {
            app.cancel_project_modal();
        }
        _ => {}
    }
}

fn handle_confirming_input(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    code: KeyCode,
) -> Result<()> {
    match code {
        KeyCode::Char('y') => {
            app.start_deploy();
            terminal.draw(|f| ui::draw(f, app))?;
            execute_plan(app)?;
            app.finish_deploy();

            // Save state after successful deploy
            let tui_state = state::capture_state(app);
            let _ = state::save_state(&app.repo_root, &tui_state);
        }
        KeyCode::Char('n') | KeyCode::Esc => {
            app.cancel_deploy();
        }
        KeyCode::Up | KeyCode::Char('k') => app.scroll_up(1),
        KeyCode::Down | KeyCode::Char('j') => app.scroll_down(1),
        KeyCode::PageUp => app.scroll_up(20),
        KeyCode::PageDown => app.scroll_down(20),
        KeyCode::Home | KeyCode::Char('g') => app.scroll_to_top(),
        KeyCode::End | KeyCode::Char('G') => app.scroll_to_bottom(),
        _ => {}
    }
    Ok(())
}

/// Build a clean preview summary from the app state (no execute_deploy calls).
/// Each item shows its name and destination paths as indented lines underneath.
fn build_preview(app: &mut App) {
    let home = dirs::home_dir().unwrap_or_default();
    let home_str = home.to_string_lossy();
    let tilde =
        |p: &std::path::Path| -> String { p.to_string_lossy().replace(home_str.as_ref(), "~") };

    let global_skills_path = tilde(&app.claude_config_dir.join("skills"));
    let global_hooks_path = tilde(&app.claude_config_dir.join("hooks"));
    let settings_path = tilde(&app.claude_config_dir.join("settings.json"));

    if app.deploy_plan.is_none() {
        return;
    }

    // Collect all lines into a Vec first, then push into deploy_output
    // (avoids borrow issues with needing &app for project_path_for_alias)
    let mut lines: Vec<String> = Vec::new();

    // Skills
    lines.push("=== Skills ===".to_string());
    for skill in &app.skill_rows {
        if !skill.enabled {
            continue;
        }
        match &skill.mode {
            AssignedMode::Skip => {
                lines.push(format!("  - {}  skipped", skill.name));
            }
            AssignedMode::Global => {
                lines.push(format!("  + {}  -> {}", skill.name, global_skills_path));
                for script in &skill.scripts {
                    if script.on_path {
                        lines.push(format!("      -> ~/.local/bin/{}", script.name));
                    }
                }
            }
            AssignedMode::Project(aliases) => {
                lines.push(format!("  + {}", skill.name));
                for alias in aliases {
                    if let Some(path) = app.project_path_for_alias(alias) {
                        lines.push(format!("      -> {}", tilde(&path.join(".claude/skills"))));
                    }
                }
            }
        }
    }

    // Hooks
    if !app.hook_rows.is_empty() {
        lines.push(String::new());
        lines.push("=== Hooks ===".to_string());
        for hook in &app.hook_rows {
            if !hook.enabled {
                continue;
            }
            if hook.mode.is_skip() {
                lines.push(format!("  - {}  skipped", hook.name));
            } else {
                lines.push(format!("  + {}  -> {}", hook.name, global_hooks_path));
            }
        }
    }

    // MCP
    if !app.mcp_rows.is_empty() {
        lines.push(String::new());
        lines.push("=== MCP ===".to_string());
        for mcp in &app.mcp_rows {
            if !mcp.enabled {
                continue;
            }
            match &mcp.mode {
                AssignedMode::Skip => {
                    lines.push(format!("  - {}  skipped", mcp.name));
                }
                AssignedMode::Global => {
                    lines.push(format!("  + {}  -> {}", mcp.name, settings_path));
                }
                AssignedMode::Project(aliases) => {
                    lines.push(format!("  + {}", mcp.name));
                    for alias in aliases {
                        if let Some(path) = app.project_path_for_alias(alias) {
                            lines.push(format!("      -> {}", tilde(&path.join(".mcp.json"))));
                        }
                    }
                }
            }
        }
    }

    // Permissions
    if !app.perm_rows.is_empty() {
        lines.push(String::new());
        lines.push("=== Permissions ===".to_string());
        for perm in &app.perm_rows {
            if !perm.enabled {
                continue;
            }
            match &perm.mode {
                AssignedMode::Skip => {
                    lines.push(format!("  - {}  skipped", perm.name));
                }
                AssignedMode::Global => {
                    lines.push(format!("  + {}  -> {}", perm.name, settings_path));
                }
                AssignedMode::Project(aliases) => {
                    lines.push(format!("  + {}", perm.name));
                    for alias in aliases {
                        if let Some(path) = app.project_path_for_alias(alias) {
                            lines.push(format!(
                                "      -> {}",
                                tilde(&path.join(".claude/settings.json"))
                            ));
                        }
                    }
                }
            }
        }
    }

    // Summary counts
    let mut deployed = 0usize;
    let mut skipped = 0usize;
    for mode in app
        .skill_rows
        .iter()
        .filter(|s| s.enabled)
        .map(|s| &s.mode)
        .chain(app.hook_rows.iter().filter(|h| h.enabled).map(|h| &h.mode))
        .chain(app.mcp_rows.iter().filter(|m| m.enabled).map(|m| &m.mode))
        .chain(app.perm_rows.iter().filter(|p| p.enabled).map(|p| &p.mode))
    {
        if mode.is_skip() {
            skipped += 1;
        } else {
            deployed += 1;
        }
    }

    lines.push(String::new());
    lines.push(format!(
        "{} to deploy, {} skipped. Press [Y] to confirm.",
        deployed, skipped
    ));

    app.deploy_output.extend(lines);
}

/// Execute the deploy plan: global pass + per-project passes.
fn execute_plan(app: &mut App) -> Result<()> {
    let plan = match &app.deploy_plan {
        Some(p) => p.clone(),
        None => return Ok(()),
    };

    // Global pass
    if !plan.global_items.is_empty() {
        app.deploy_output
            .push("=== Deploying -> global ===".to_string());
        app.deploy_output
            .push(format!("  Items: {}", plan.global_items.join(", ")));

        let ctx = DeployContext {
            repo_root: app.repo_root.clone(),
            claude_config_dir: app.claude_config_dir.clone(),
            project_path: None,
            on_path: false,
            dry_run: false,
            skip_permissions: false,
            include: plan.global_items.clone(),
            exclude: vec![],
            profile_data: Value::Object(Default::default()),
            quiet: true,
            on_path_scripts: plan.on_path_scripts.clone(),
        };

        run_deploy_pass(app, &ctx, "global");
        validate_json_files(app, None);
    }

    // Per-project passes
    for (project_path, items) in &plan.project_items {
        // Find alias for this project path
        let alias = app
            .projects
            .iter()
            .find(|p| p.path == *project_path)
            .map(|p| p.alias.clone())
            .unwrap_or_else(|| {
                project_path
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            });
        let target_label = format!("project:{}", alias);
        let path_display = project_path.to_string_lossy();
        app.deploy_output
            .push(format!("=== Deploying -> project: {} ===", path_display));
        app.deploy_output
            .push(format!("  Items: {}", items.join(", ")));

        let ctx = DeployContext {
            repo_root: app.repo_root.clone(),
            claude_config_dir: app.claude_config_dir.clone(),
            project_path: Some(project_path.clone()),
            on_path: false,
            dry_run: false,
            skip_permissions: false,
            include: items.clone(),
            exclude: vec![],
            profile_data: Value::Object(Default::default()),
            quiet: true,
            on_path_scripts: HashMap::new(),
        };

        run_deploy_pass(app, &ctx, &target_label);
        validate_json_files(app, Some(project_path));
    }

    append_summary(&app.deploy_results, &mut app.deploy_output);
    app.deploy_output.push("Deploy complete.".to_string());

    Ok(())
}

fn run_deploy_pass(app: &mut App, ctx: &DeployContext, target_label: &str) {
    let captured = capture_stdout(|| execute_deploy(ctx));

    match captured {
        Ok((result, stdout_text)) => {
            for line in stdout_text.lines() {
                app.deploy_output.push(line.to_string());
            }
            parse_deploy_results(&stdout_text, target_label, &mut app.deploy_results);
            if let Err(e) = result {
                app.deploy_output.push(format!("ERROR: {}", e));
            }
            app.deploy_output.push(String::new());
        }
        Err(e) => {
            app.deploy_output.push(format!("ERROR: {}", e));
        }
    }
}

/// Append a structured summary section to deploy output.
/// Order: Skipped -> Deployed (with details) -> Errors
fn append_summary(results: &DeployResults, output: &mut Vec<String>) {
    output.push(String::new());
    output.push("=== Summary ===".to_string());

    let skipped = results.skipped();
    let deployed = results.deployed();
    let errors = results.errors();

    // Skipped first (less interesting, scrolls off top)
    if !skipped.is_empty() {
        output.push(format!("  Skipped ({}):", skipped.len()));
        for r in &skipped {
            output.push(format!("    - {}", r.name));
        }
        output.push(String::new());
    }

    // Deployed with detail lines (most interesting, at bottom)
    if !deployed.is_empty() {
        output.push(format!("  Deployed ({}):", deployed.len()));
        for r in &deployed {
            let targets = r.targets.join(", ");
            output.push(format!("    + {} -> {}", r.name, targets));
            for detail in &r.details {
                output.push(format!("        {}", detail));
            }
        }
        output.push(String::new());
    }

    // Errors last
    if !errors.is_empty() {
        output.push(format!("  Errors ({}):", errors.len()));
        for r in &errors {
            if let DeployStatus::Error(msg) = &r.status {
                output.push(format!("    ! {} ({})", r.name, msg));
            }
        }
        output.push(String::new());
    }

    if deployed.is_empty() && skipped.is_empty() && errors.is_empty() {
        output.push("  (no items processed)".to_string());
        output.push(String::new());
    }
}

/// Parse deploy output to extract per-item results with detail lines.
/// Uses a state machine: category headers set context, Deployed/Skipped lines
/// set current item, indented lines (OK:, Linked:, > ln) append as details.
fn parse_deploy_results(stdout: &str, target_label: &str, results: &mut DeployResults) {
    let mut current_category = None;
    let mut current_item: Option<String> = None;
    let mut current_details: Vec<String> = Vec::new();
    let mut current_status: Option<DeployStatus> = None;
    let mut current_cat: Option<Category> = None;

    let flush = |item: &mut Option<String>,
                 details: &mut Vec<String>,
                 status: &mut Option<DeployStatus>,
                 cat: &mut Option<Category>,
                 results: &mut DeployResults,
                 target: &str| {
        if let (Some(name), Some(st), Some(c)) = (item.take(), status.take(), cat.take()) {
            results.record(&name, c, st, target, details.drain(..).collect());
        }
        details.clear();
    };

    for line in stdout.lines() {
        let trimmed = line.trim();

        // Category headers
        if trimmed == "=== Skills ===" {
            flush(
                &mut current_item,
                &mut current_details,
                &mut current_status,
                &mut current_cat,
                results,
                target_label,
            );
            current_category = Some(Category::Skills);
            continue;
        } else if trimmed == "=== Hooks ===" {
            flush(
                &mut current_item,
                &mut current_details,
                &mut current_status,
                &mut current_cat,
                results,
                target_label,
            );
            current_category = Some(Category::Hooks);
            continue;
        } else if trimmed == "=== MCP ===" {
            flush(
                &mut current_item,
                &mut current_details,
                &mut current_status,
                &mut current_cat,
                results,
                target_label,
            );
            current_category = Some(Category::Mcp);
            continue;
        } else if trimmed == "=== Permissions ===" {
            flush(
                &mut current_item,
                &mut current_details,
                &mut current_status,
                &mut current_cat,
                results,
                target_label,
            );
            current_category = Some(Category::Permissions);
            continue;
        }

        if let Some(ref cat) = current_category {
            // Item status lines
            if let Some(name) = trimmed.strip_prefix("Deployed: ") {
                flush(
                    &mut current_item,
                    &mut current_details,
                    &mut current_status,
                    &mut current_cat,
                    results,
                    target_label,
                );
                let name = name.strip_prefix("hook ").unwrap_or(name);
                current_item = Some(name.to_string());
                current_status = Some(DeployStatus::Deployed);
                current_cat = Some(cat.clone());
            } else if let Some(name) = trimmed.strip_prefix("Included: ") {
                flush(
                    &mut current_item,
                    &mut current_details,
                    &mut current_status,
                    &mut current_cat,
                    results,
                    target_label,
                );
                current_item = Some(name.to_string());
                current_status = Some(DeployStatus::Deployed);
                current_cat = Some(cat.clone());
            } else if let Some(rest) = trimmed.strip_prefix("Skipped: ") {
                flush(
                    &mut current_item,
                    &mut current_details,
                    &mut current_status,
                    &mut current_cat,
                    results,
                    target_label,
                );
                let rest = rest.strip_prefix("hook ").unwrap_or(rest);
                let (name, reason) = if let Some(paren_pos) = rest.rfind('(') {
                    let name = rest[..paren_pos].trim().to_string();
                    let reason = rest[paren_pos + 1..].trim_end_matches(')').to_string();
                    (name, reason)
                } else {
                    (rest.to_string(), "unknown".to_string())
                };
                current_item = Some(name.to_string());
                current_status = Some(DeployStatus::Skipped(reason));
                current_cat = Some(cat.clone());
            } else if trimmed.starts_with("OK:")
                || trimmed.starts_with("Linked:")
                || trimmed.starts_with("> ln")
            {
                // Detail line for current item
                current_details.push(trimmed.to_string());
            }
        }
    }

    // Flush last item
    flush(
        &mut current_item,
        &mut current_details,
        &mut current_status,
        &mut current_cat,
        results,
        target_label,
    );
}

/// Validate JSON files after a deploy pass.
fn validate_json_files(app: &mut App, project_path: Option<&PathBuf>) {
    let files_to_check: Vec<PathBuf> = if let Some(pp) = project_path {
        vec![pp.join(".claude/settings.json"), pp.join(".mcp.json")]
    } else {
        vec![app.claude_config_dir.join("settings.json")]
    };

    for path in files_to_check {
        if path.exists() {
            match std::fs::read_to_string(&path) {
                Ok(content) => {
                    if let Err(e) = serde_json::from_str::<Value>(&content) {
                        app.deploy_output.push(format!(
                            "  WARNING: {} is not valid JSON: {}",
                            tilde_path(&path),
                            e
                        ));
                    }
                }
                Err(e) => {
                    app.deploy_output.push(format!(
                        "  WARNING: Could not read {}: {}",
                        tilde_path(&path),
                        e
                    ));
                }
            }
        }
    }
}

/// Replace home directory with ~ in a path for display.
fn tilde_path(p: &Path) -> String {
    let home = dirs::home_dir().unwrap_or_default();
    p.to_string_lossy()
        .replace(home.to_string_lossy().as_ref(), "~")
}

/// Capture stdout from a closure by redirecting fd 1 to a pipe.
fn capture_stdout<F, R>(f: F) -> Result<(R, String)>
where
    F: FnOnce() -> R,
{
    use std::os::unix::io::FromRawFd;

    let (read_fd, write_fd) = {
        let mut fds = [0i32; 2];
        let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
        if ret != 0 {
            anyhow::bail!("pipe() failed");
        }
        (fds[0], fds[1])
    };

    let stdout_fd = io::stdout().as_raw_fd();
    let saved_stdout = unsafe { libc::dup(stdout_fd) };
    if saved_stdout < 0 {
        unsafe {
            libc::close(read_fd);
            libc::close(write_fd);
        }
        anyhow::bail!("dup() failed");
    }

    unsafe {
        libc::dup2(write_fd, stdout_fd);
        libc::close(write_fd);
    }

    let result = f();
    let _ = io::stdout().flush();

    unsafe {
        libc::dup2(saved_stdout, stdout_fd);
        libc::close(saved_stdout);
    }

    let mut read_file = unsafe { std::fs::File::from_raw_fd(read_fd) };
    let mut captured = String::new();
    unsafe {
        let flags = libc::fcntl(read_fd, libc::F_GETFL);
        libc::fcntl(read_fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
    let _ = io::Read::read_to_string(&mut read_file, &mut captured);

    Ok((result, captured))
}

/// Tab-complete a file path in the project input buffer.
fn tab_complete_path(input: &mut String) {
    let path = input.trim();
    if path.is_empty() {
        if let Some(home) = dirs::home_dir() {
            *input = format!("{}/", home.display());
        }
        return;
    }

    let expanded_path = expand_tilde(path);

    if expanded_path.is_dir() && !input.ends_with('/') {
        *input = format!("{}/", expanded_path.display());
        return;
    }

    let (search_dir, prefix) = if expanded_path.is_dir() {
        (expanded_path, String::new())
    } else {
        let parent = expanded_path
            .parent()
            .unwrap_or(&PathBuf::from("/"))
            .to_path_buf();
        let file_part = expanded_path
            .file_name()
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_default();
        (parent, file_part)
    };

    let entries = match std::fs::read_dir(&search_dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };

    let mut matches: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|name| !name.starts_with('.'))
        .filter(|name| name.starts_with(&prefix))
        .collect();
    matches.sort();

    if matches.is_empty() {
        return;
    }

    if matches.len() == 1 {
        let completed = search_dir.join(&matches[0]);
        *input = format!("{}/", completed.display());
    } else {
        let lcp = longest_common_prefix(&matches);
        if lcp.len() > prefix.len() {
            let completed = search_dir.join(&lcp);
            *input = format!("{}", completed.display());
        }
    }
}

fn longest_common_prefix(strings: &[String]) -> String {
    if strings.is_empty() {
        return String::new();
    }
    let first = &strings[0];
    let mut len = first.len();
    for s in &strings[1..] {
        len = len.min(s.len());
        for (i, (a, b)) in first.chars().zip(s.chars()).enumerate() {
            if a != b {
                len = len.min(i);
                break;
            }
        }
    }
    first[..len].to_string()
}
