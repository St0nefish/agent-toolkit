// tui/ui.rs - Stateless ratatui rendering

use super::app::{
    tilde_path, App, AssignedMode, InputMode, SkillPos, TAB_HOOKS, TAB_MCP, TAB_NAMES,
    TAB_PERMISSIONS, TAB_PROJECTS, TAB_SKILLS,
};
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, Paragraph};
use ratatui::Frame;

// ---------------------------------------------------------------------------
// Style helpers (reduce repeated style construction)
// ---------------------------------------------------------------------------

/// Color for a mode badge.
fn mode_color(mode: &AssignedMode) -> Color {
    match mode {
        AssignedMode::Global => Color::Green,
        AssignedMode::Skip => Color::DarkGray,
        AssignedMode::Project(aliases) => {
            if aliases.is_empty() {
                Color::DarkGray
            } else {
                Color::Cyan
            }
        }
    }
}

/// Format mode badge padded to fixed width.
fn mode_badge(mode: &AssignedMode) -> String {
    let label = mode.badge();
    format!("{:<8}", label)
}

/// Style for the cursor indicator column.
fn cursor_style(is_cursor: bool) -> Style {
    if is_cursor {
        Style::default()
            .fg(Color::White)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
    }
}

/// Style for an item's name, accounting for cursor and enabled state.
fn name_style(is_cursor: bool, enabled: bool) -> Style {
    if is_cursor {
        Style::default()
            .fg(Color::White)
            .add_modifier(Modifier::BOLD)
    } else if !enabled {
        Style::default()
            .fg(Color::DarkGray)
            .add_modifier(Modifier::DIM)
    } else {
        Style::default().fg(Color::White)
    }
}

/// Cursor arrow indicator.
fn cursor_char(is_cursor: bool) -> &'static str {
    if is_cursor {
        "▶"
    } else {
        " "
    }
}

/// Center a modal of given dimensions within an area.
fn center_modal(area: Rect, width: u16, height: u16) -> Rect {
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect::new(x, y, width, height)
}

/// Build the common prefix spans for a row: cursor indicator + badge + padded name.
fn build_row_spans(
    is_cursor: bool,
    mode: &AssignedMode,
    enabled: bool,
    name: &str,
    max_name_width: usize,
) -> Vec<Span<'static>> {
    let color = if !enabled {
        Color::DarkGray
    } else {
        mode_color(mode)
    };
    let mut style = Style::default().fg(color);
    if !enabled {
        style = style.add_modifier(Modifier::DIM);
    }
    let padded_name = format!("{:<width$}", name, width = max_name_width);

    vec![
        Span::styled(
            format!("  {} ", cursor_char(is_cursor)),
            cursor_style(is_cursor),
        ),
        Span::styled(format!("[{}] ", mode_badge(mode)), style),
        Span::styled(padded_name, name_style(is_cursor, enabled)),
    ]
}

/// Main draw function.
pub fn draw(frame: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // header + tab bar
            Constraint::Min(5),    // content
            Constraint::Length(3), // footer
        ])
        .split(frame.area());

    // Track content area height for scroll guards
    app.content_height = chunks[1].height.saturating_sub(2) as usize;

    draw_header(frame, app, chunks[0]);

    match app.input_mode {
        InputMode::Normal | InputMode::AddProject | InputMode::EditAlias => {
            draw_tab_content(frame, app, chunks[1]);
        }
        InputMode::SelectProjects => {
            draw_tab_content(frame, app, chunks[1]);
            draw_project_modal(frame, app, chunks[1]);
        }
        InputMode::ScriptConfig => {
            draw_tab_content(frame, app, chunks[1]);
            draw_script_config_modal(frame, app, chunks[1]);
        }
        InputMode::InfoView => {
            draw_tab_content(frame, app, chunks[1]);
            draw_info_modal(frame, app, chunks[1]);
        }
        InputMode::DryRunning | InputMode::Confirming | InputMode::Deploying | InputMode::Done => {
            draw_deploy_output(frame, app, chunks[1]);
        }
    }

    draw_footer(frame, app, chunks[2]);
}

fn draw_header(frame: &mut Frame, app: &App, area: Rect) {
    let repo_display = tilde_path(&app.repo_root);
    let config_display = tilde_path(&app.claude_config_dir);

    // Build tab bar
    let mut tab_spans = vec![Span::raw(" ")];
    for (i, name) in TAB_NAMES.iter().enumerate() {
        if i == app.active_tab {
            tab_spans.push(Span::styled(
                format!("[{}]", name),
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            ));
        } else {
            tab_spans.push(Span::styled(
                format!(" {} ", name),
                Style::default().fg(Color::DarkGray),
            ));
        }
        tab_spans.push(Span::raw("  "));
    }

    let lines = vec![
        Line::from(vec![Span::styled(
            " Claude Toolkit Deploy ",
            Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )]),
        Line::from(vec![Span::raw(format!(
            "  Repo: {:<32} Config: {}",
            repo_display, config_display
        ))]),
        Line::from(tab_spans),
    ];

    let block = Block::default().borders(Borders::BOTTOM);
    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}

fn draw_tab_content(frame: &mut Frame, app: &App, area: Rect) {
    match app.active_tab {
        TAB_SKILLS => draw_skills_tab(frame, app, area),
        TAB_HOOKS => draw_simple_tab(frame, app, &app.hook_rows, area),
        TAB_MCP => draw_simple_tab(frame, app, &app.mcp_rows, area),
        TAB_PERMISSIONS => draw_simple_tab(frame, app, &app.perm_rows, area),
        TAB_PROJECTS => draw_projects_tab(frame, app, area),
        _ => {}
    }
}

fn draw_skills_tab(frame: &mut Frame, app: &App, area: Rect) {
    let cursor_idx = app.cursors[TAB_SKILLS];
    let mut list_items: Vec<ListItem> = Vec::new();

    let max_name_width = app
        .skill_rows
        .iter()
        .map(|s| s.name.len())
        .max()
        .unwrap_or(0);

    for (idx, skill) in app.skill_rows.iter().enumerate() {
        let is_cursor = idx == cursor_idx;
        let mut spans = build_row_spans(
            is_cursor,
            &skill.mode,
            skill.enabled,
            &skill.name,
            max_name_width,
        );

        // Indicators column (fixed-width): "*[N]" padded to 6 chars
        let has_path = skill.mode.is_global() && skill.scripts.iter().any(|s| s.on_path);
        let has_scripts = !skill.scripts.is_empty() && skill.enabled;

        if has_path || has_scripts {
            if has_path {
                spans.push(Span::styled(
                    "*",
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                ));
            } else {
                spans.push(Span::raw(" "));
            }
            if has_scripts {
                let count_str = format!("[{}]", skill.scripts.len());
                let pad = 5usize.saturating_sub(count_str.len());
                spans.push(Span::styled(
                    count_str,
                    Style::default().fg(Color::DarkGray),
                ));
                if pad > 0 {
                    spans.push(Span::raw(" ".repeat(pad)));
                }
            } else {
                spans.push(Span::raw("     "));
            }
        } else {
            spans.push(Span::raw("      "));
        }

        if let Some(label) = skill.mode.project_label() {
            spans.push(Span::styled(
                format!("  {}", label),
                Style::default().fg(Color::Cyan),
            ));
        }

        list_items.push(ListItem::new(Line::from(spans)));
    }

    let list = List::new(list_items).block(Block::default().borders(Borders::NONE));
    frame.render_widget(list, area);
}

fn draw_simple_tab(frame: &mut Frame, app: &App, rows: &[super::app::SimpleRow], area: Rect) {
    let cursor_idx = app.cursors[app.active_tab];
    let mut list_items: Vec<ListItem> = Vec::new();

    let max_name_width = rows.iter().map(|r| r.name.len()).max().unwrap_or(0);

    for (idx, row) in rows.iter().enumerate() {
        let is_cursor = idx == cursor_idx;
        let mut spans =
            build_row_spans(is_cursor, &row.mode, row.enabled, &row.name, max_name_width);

        if let Some(label) = row.mode.project_label() {
            spans.push(Span::styled(
                format!("  {}", label),
                Style::default().fg(Color::Cyan),
            ));
        }

        list_items.push(ListItem::new(Line::from(spans)));
    }

    let list = List::new(list_items).block(Block::default().borders(Borders::NONE));
    frame.render_widget(list, area);
}

fn draw_projects_tab(frame: &mut Frame, app: &App, area: Rect) {
    let cursor_idx = app.cursors[TAB_PROJECTS];
    let mut list_items: Vec<ListItem> = Vec::new();

    if app.projects.is_empty() {
        list_items.push(ListItem::new(Line::from(Span::styled(
            "  No projects configured. Press [A] to add one.",
            Style::default().fg(Color::DarkGray),
        ))));
    }

    for (idx, project) in app.projects.iter().enumerate() {
        let is_cursor = idx == cursor_idx;
        let path_display = tilde_path(&project.path);

        let line = Line::from(vec![
            Span::styled(
                format!("  {} ", cursor_char(is_cursor)),
                cursor_style(is_cursor),
            ),
            Span::styled(format!("{}  ", idx + 1), Style::default().fg(Color::Cyan)),
            Span::styled(
                format!("{:<12} ", project.alias),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(path_display, cursor_style(is_cursor).fg(Color::White)),
        ]);

        list_items.push(ListItem::new(line));
    }

    let list = List::new(list_items).block(Block::default().borders(Borders::NONE));
    frame.render_widget(list, area);
}

fn draw_project_modal(frame: &mut Frame, app: &App, area: Rect) {
    let modal_height = (app.projects.len() as u16 + 4).min(area.height.saturating_sub(2));
    let modal_width = 50u16.min(area.width.saturating_sub(4));
    let modal_area = center_modal(area, modal_width, modal_height);

    frame.render_widget(Clear, modal_area);

    let title = format!(" Select Projects: {} ", app.modal_item_name);
    let inner_height = modal_height.saturating_sub(2) as usize;

    let mut lines: Vec<Line> = Vec::new();
    for (idx, project) in app.projects.iter().enumerate() {
        if idx >= inner_height.saturating_sub(1) {
            break;
        }
        let checked = app.modal_selections.get(idx).copied().unwrap_or(false);
        let checkbox = if checked { "[x]" } else { "[ ]" };
        let is_cursor = idx == app.modal_cursor;
        let style = cursor_style(is_cursor).fg(Color::White);

        lines.push(Line::from(vec![
            Span::styled(format!(" {} ", cursor_char(is_cursor)), style),
            Span::styled(format!("{} ", checkbox), Style::default().fg(Color::Cyan)),
            Span::styled(
                format!("{:<10} ", project.alias),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(tilde_path(&project.path), style),
        ]));
    }

    // Footer hint
    lines.push(Line::from(vec![
        Span::styled(" [Space]", Style::default().fg(Color::Cyan)),
        Span::raw(" toggle  "),
        Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
        Span::raw(" done  "),
        Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
        Span::raw(" cancel"),
    ]));

    let block = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, modal_area);
}

fn draw_script_config_modal(frame: &mut Frame, app: &App, area: Rect) {
    let script_count = app.modal_selections.len();
    let modal_height = (script_count as u16 + 4).min(area.height.saturating_sub(2));
    let modal_width = 60u16.min(area.width.saturating_sub(4));
    let modal_area = center_modal(area, modal_width, modal_height);

    frame.render_widget(Clear, modal_area);

    let title = format!(" Scripts: {}/bin/ ", app.modal_item_name);
    let inner_height = modal_height.saturating_sub(2) as usize;

    let mut lines: Vec<Line> = Vec::new();

    let script_names: Vec<String> = app
        .skill_rows
        .iter()
        .find(|s| s.name == app.modal_item_name)
        .map(|s| s.scripts.iter().map(|sc| sc.name.clone()).collect())
        .unwrap_or_default();

    for (idx, name) in script_names.iter().enumerate() {
        if idx >= inner_height.saturating_sub(1) {
            break;
        }
        let checked = app.modal_selections.get(idx).copied().unwrap_or(false);
        let checkbox = if checked { "[x]" } else { "[ ]" };
        let is_cursor = idx == app.modal_cursor;
        let style = cursor_style(is_cursor).fg(Color::White);

        lines.push(Line::from(vec![
            Span::styled(format!(" {} ", cursor_char(is_cursor)), style),
            Span::styled(
                format!("{} ", checkbox),
                Style::default().fg(if checked { Color::Yellow } else { Color::Cyan }),
            ),
            Span::styled(name.as_str(), style),
        ]));
    }

    // Footer hint
    lines.push(Line::from(vec![
        Span::styled(" [Space]", Style::default().fg(Color::Cyan)),
        Span::raw(" toggle PATH  "),
        Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
        Span::raw(" done  "),
        Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
        Span::raw(" cancel"),
    ]));

    let block = Block::default()
        .title(title)
        .title_bottom(Line::from(" toggle PATH deployment ").centered())
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow));
    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, modal_area);
}

fn draw_info_modal(frame: &mut Frame, app: &App, area: Rect) {
    let modal_width = area.width.saturating_sub(4).min(100);
    let modal_height = area.height.saturating_sub(2);
    let modal_area = center_modal(area, modal_width, modal_height);

    frame.render_widget(Clear, modal_area);

    let visible_lines = modal_height.saturating_sub(2) as usize;
    let total = app.info_content.len();
    let start = app.info_scroll;
    let end = (start + visible_lines).min(total);

    let title = format!(" {} ", app.info_title);
    let scroll_info = if total > visible_lines {
        format!(" {}-{}/{} ", start + 1, end, total)
    } else {
        String::new()
    };

    let lines: Vec<Line> = app.info_content[start..end]
        .iter()
        .map(|s| {
            let trimmed = s.trim();
            if trimmed.starts_with("---") && trimmed.ends_with("---") {
                Line::from(Span::styled(
                    s.as_str(),
                    Style::default()
                        .fg(Color::Cyan)
                        .add_modifier(Modifier::BOLD),
                ))
            } else if trimmed.starts_with('#') {
                Line::from(Span::styled(
                    s.as_str(),
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                ))
            } else if trimmed.starts_with("Description:") {
                Line::from(Span::styled(s.as_str(), Style::default().fg(Color::Green)))
            } else {
                Line::from(Span::raw(s.as_str()))
            }
        })
        .collect();

    let block = Block::default()
        .title(title)
        .title_bottom(
            Line::from(vec![
                Span::raw(scroll_info),
                Span::styled(" [↑↓/jk]", Style::default().fg(Color::DarkGray)),
                Span::styled(" scroll  ", Style::default().fg(Color::DarkGray)),
                Span::styled("[Esc/i]", Style::default().fg(Color::DarkGray)),
                Span::styled(" close ", Style::default().fg(Color::DarkGray)),
            ])
            .centered(),
        )
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, modal_area);
}

fn draw_deploy_output(frame: &mut Frame, app: &App, area: Rect) {
    let visible_lines = area.height.saturating_sub(2) as usize;
    let total = app.deploy_output.len();
    let can_scroll = total > visible_lines;

    let end = total.saturating_sub(app.scroll_offset);
    let start = end.saturating_sub(visible_lines);

    let title = match app.input_mode {
        InputMode::DryRunning => " Previewing... ".to_string(),
        InputMode::Confirming => " Preview (review changes) ".to_string(),
        InputMode::Deploying => " Deploying... ".to_string(),
        InputMode::Done => " Deploy Complete ".to_string(),
        _ => String::new(),
    };

    let title = if can_scroll && app.scroll_offset > 0 {
        let pct = if total <= visible_lines {
            100
        } else {
            let max_top = total.saturating_sub(visible_lines);
            100 - (start * 100 / max_top)
        };
        format!("{} [{}/{}  {}%] ", title.trim(), start + 1, total, pct)
    } else {
        title
    };

    let lines: Vec<Line> = app.deploy_output[start..end]
        .iter()
        .map(|s| {
            let trimmed = s.trim();
            if trimmed.starts_with("===") && trimmed.ends_with("===") {
                Line::from(Span::styled(
                    s.as_str(),
                    Style::default()
                        .fg(Color::Cyan)
                        .add_modifier(Modifier::BOLD),
                ))
            } else if trimmed.starts_with("Deployed:")
                || trimmed.starts_with("Included:")
                || trimmed.starts_with('+')
            {
                Line::from(Span::styled(s.as_str(), Style::default().fg(Color::Green)))
            } else if trimmed.starts_with("Skipped:") || trimmed.starts_with('-') {
                Line::from(Span::styled(s.as_str(), Style::default().fg(Color::Yellow)))
            } else if trimmed.starts_with("ERROR:") || trimmed.starts_with('!') {
                Line::from(Span::styled(s.as_str(), Style::default().fg(Color::Red)))
            } else if trimmed.starts_with("WARNING:") {
                Line::from(Span::styled(
                    s.as_str(),
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                ))
            } else if trimmed.starts_with('>') {
                Line::from(Span::styled(
                    s.as_str(),
                    Style::default().fg(Color::DarkGray),
                ))
            } else {
                Line::from(Span::raw(s.as_str()))
            }
        })
        .collect();

    let scroll_hint = if can_scroll {
        " [scroll: arrows/jk] "
    } else {
        ""
    };

    let block = Block::default()
        .title(title)
        .title_bottom(Line::from(scroll_hint).centered())
        .borders(Borders::ALL);
    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}

fn draw_footer(frame: &mut Frame, app: &App, area: Rect) {
    let content = match app.input_mode {
        InputMode::Normal => {
            let mut spans = vec![
                Span::styled(" [Tab/S-Tab]", Style::default().fg(Color::Cyan)),
                Span::raw(" switch  "),
            ];

            match app.active_tab {
                TAB_SKILLS => {
                    spans.extend_from_slice(&[
                        Span::styled("[Space]", Style::default().fg(Color::Cyan)),
                        Span::raw(" cycle  "),
                    ]);
                    // Show T key hint if current skill has scripts
                    if let Some(SkillPos::Skill(si)) = app.current_skill_pos() {
                        if !app.skill_rows[si].scripts.is_empty()
                            && app.skill_rows[si].enabled
                            && app.skill_rows[si].mode.is_global()
                        {
                            spans.extend_from_slice(&[
                                Span::styled("[T]", Style::default().fg(Color::Cyan)),
                                Span::raw(" scripts  "),
                            ]);
                        }
                    }
                    if !app.projects.is_empty() {
                        spans.extend_from_slice(&[
                            Span::styled("[P]", Style::default().fg(Color::Cyan)),
                            Span::raw(" projects  "),
                        ]);
                    }
                    spans.extend_from_slice(&[
                        Span::styled("[I]", Style::default().fg(Color::DarkGray)),
                        Span::raw(" info  "),
                    ]);
                }
                TAB_HOOKS => {
                    spans.extend_from_slice(&[
                        Span::styled("[Space]", Style::default().fg(Color::Cyan)),
                        Span::raw(" cycle  "),
                        Span::styled("[I]", Style::default().fg(Color::DarkGray)),
                        Span::raw(" info  "),
                    ]);
                }
                TAB_MCP | TAB_PERMISSIONS => {
                    spans.extend_from_slice(&[
                        Span::styled("[Space]", Style::default().fg(Color::Cyan)),
                        Span::raw(" cycle  "),
                    ]);
                    if !app.projects.is_empty() {
                        spans.extend_from_slice(&[
                            Span::styled("[P]", Style::default().fg(Color::Cyan)),
                            Span::raw(" projects  "),
                        ]);
                    }
                    spans.extend_from_slice(&[
                        Span::styled("[I]", Style::default().fg(Color::DarkGray)),
                        Span::raw(" info  "),
                    ]);
                }
                TAB_PROJECTS => {
                    spans.extend_from_slice(&[
                        Span::styled("[A]", Style::default().fg(Color::Cyan)),
                        Span::raw(" add  "),
                        Span::styled("[D]", Style::default().fg(Color::Cyan)),
                        Span::raw(" delete  "),
                        Span::styled("[E]", Style::default().fg(Color::Cyan)),
                        Span::raw(" edit alias  "),
                    ]);
                }
                _ => {}
            }

            spans.extend_from_slice(&[
                Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
                Span::raw(" deploy  "),
                Span::styled("[Q]", Style::default().fg(Color::Cyan)),
                Span::raw(" quit"),
            ]);

            Line::from(spans)
        }
        InputMode::AddProject => Line::from(vec![
            Span::raw("  Project path: "),
            Span::styled(&app.project_input, Style::default().fg(Color::Yellow)),
            Span::styled("\u{2588}", Style::default().fg(Color::Yellow)),
            Span::raw("  "),
            Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
            Span::raw(" confirm  "),
            Span::styled("[Tab]", Style::default().fg(Color::Cyan)),
            Span::raw(" complete  "),
            Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
            Span::raw(" cancel"),
        ]),
        InputMode::EditAlias => Line::from(vec![
            Span::raw("  Alias: "),
            Span::styled(&app.alias_input, Style::default().fg(Color::Yellow)),
            Span::styled("\u{2588}", Style::default().fg(Color::Yellow)),
            Span::raw("  "),
            Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
            Span::raw(" confirm  "),
            Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
            Span::raw(" cancel"),
        ]),
        InputMode::SelectProjects => Line::from(vec![
            Span::raw("  "),
            Span::styled("[Space]", Style::default().fg(Color::Cyan)),
            Span::raw(" toggle  "),
            Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
            Span::raw(" done  "),
            Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
            Span::raw(" cancel"),
        ]),
        InputMode::ScriptConfig => Line::from(vec![
            Span::raw("  "),
            Span::styled("[Space]", Style::default().fg(Color::Cyan)),
            Span::raw(" toggle PATH  "),
            Span::styled("[Enter]", Style::default().fg(Color::Cyan)),
            Span::raw(" done  "),
            Span::styled("[Esc]", Style::default().fg(Color::Cyan)),
            Span::raw(" cancel"),
        ]),
        InputMode::InfoView => Line::from(vec![
            Span::raw("  "),
            Span::styled("[↑↓/jk]", Style::default().fg(Color::Cyan)),
            Span::raw(" scroll  "),
            Span::styled("[PgUp/PgDn]", Style::default().fg(Color::Cyan)),
            Span::raw(" page  "),
            Span::styled("[g/G]", Style::default().fg(Color::Cyan)),
            Span::raw(" top/bottom  "),
            Span::styled("[Esc/i]", Style::default().fg(Color::Cyan)),
            Span::raw(" close"),
        ]),
        InputMode::DryRunning => Line::from(Span::styled(
            "  Previewing...",
            Style::default().fg(Color::Yellow),
        )),
        InputMode::Confirming => Line::from(vec![
            Span::raw("  Apply? "),
            Span::styled("[Y]", Style::default().fg(Color::Green)),
            Span::raw(" yes  "),
            Span::styled("[N/Esc]", Style::default().fg(Color::Red)),
            Span::raw(" cancel  "),
            Span::styled("[arrows/jk]", Style::default().fg(Color::DarkGray)),
            Span::styled(" scroll  ", Style::default().fg(Color::DarkGray)),
            Span::styled("[g/G]", Style::default().fg(Color::DarkGray)),
            Span::styled(" top/bottom", Style::default().fg(Color::DarkGray)),
        ]),
        InputMode::Deploying => Line::from(Span::styled(
            "  Deploying...",
            Style::default().fg(Color::Yellow),
        )),
        InputMode::Done => {
            let mut spans = vec![Span::raw("  ")];

            let deployed = app.deploy_results.deployed().len();
            let skipped = app.deploy_results.skipped().len();

            if deployed > 0 {
                spans.push(Span::styled(
                    format!("{} deployed  ", deployed),
                    Style::default().fg(Color::Green),
                ));
            }
            if skipped > 0 {
                spans.push(Span::styled(
                    format!("{} skipped  ", skipped),
                    Style::default().fg(Color::Yellow),
                ));
            }

            spans.push(Span::styled(
                "[arrows/jk]",
                Style::default().fg(Color::DarkGray),
            ));
            spans.push(Span::styled(
                " scroll  ",
                Style::default().fg(Color::DarkGray),
            ));
            spans.push(Span::styled("[Q/Esc]", Style::default().fg(Color::Cyan)));
            spans.push(Span::raw(" quit"));

            Line::from(spans)
        }
    };

    let block = Block::default().borders(Borders::TOP);
    let paragraph = Paragraph::new(content).block(block);
    frame.render_widget(paragraph, area);
}
