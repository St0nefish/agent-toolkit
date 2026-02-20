// tui/ui.rs - Stateless ratatui rendering

use super::app::{
    App, AssignedMode, InputMode, SkillPos, TAB_COUNT, TAB_HOOKS, TAB_MCP, TAB_NAMES,
    TAB_PERMISSIONS, TAB_PROJECTS, TAB_SKILLS,
};
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, Paragraph};
use ratatui::Frame;

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

/// Main draw function.
pub fn draw(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // header + tab bar
            Constraint::Min(5),    // content
            Constraint::Length(3), // footer
        ])
        .split(frame.area());

    draw_header(frame, app, chunks[0]);

    match app.input_mode {
        InputMode::Normal | InputMode::AddProject | InputMode::EditAlias => {
            draw_tab_content(frame, app, chunks[1]);
        }
        InputMode::SelectProjects => {
            draw_tab_content(frame, app, chunks[1]);
            draw_project_modal(frame, app, chunks[1]);
        }
        InputMode::DryRunning | InputMode::Confirming | InputMode::Deploying | InputMode::Done => {
            draw_deploy_output(frame, app, chunks[1]);
        }
    }

    draw_footer(frame, app, chunks[2]);
}

fn draw_header(frame: &mut Frame, app: &App, area: Rect) {
    let repo_display = app.repo_root.to_string_lossy().replace(
        dirs::home_dir()
            .unwrap_or_default()
            .to_string_lossy()
            .as_ref(),
        "~",
    );
    let config_display = app.claude_config_dir.to_string_lossy().replace(
        dirs::home_dir()
            .unwrap_or_default()
            .to_string_lossy()
            .as_ref(),
        "~",
    );

    // Build tab bar
    let mut tab_spans = vec![Span::raw(" ")];
    for i in 0..TAB_COUNT {
        if i == app.active_tab {
            tab_spans.push(Span::styled(
                format!("[{}]", TAB_NAMES[i]),
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            ));
        } else {
            tab_spans.push(Span::styled(
                format!(" {} ", TAB_NAMES[i]),
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
    let cursor_flat = app.cursors[TAB_SKILLS];
    let mut list_items: Vec<ListItem> = Vec::new();
    let mut flat_idx = 0;

    // Compute max name width for column alignment
    let max_name_width = app
        .skill_rows
        .iter()
        .map(|s| s.name.len())
        .max()
        .unwrap_or(0);

    // Badge is always "GLOBAL ", "PROJECT", or "SKIP   " — fixed at 7 chars
    // Layout: "  ▶ [BADGE  ] name·····  projects"
    //         "  ▶           script [PATH]"

    for skill in &app.skill_rows {
        let is_cursor = flat_idx == cursor_flat;
        let color = if !skill.enabled {
            Color::DarkGray
        } else {
            mode_color(&skill.mode)
        };

        let cursor_char = if is_cursor { "▶" } else { " " };
        let badge = mode_badge(&skill.mode);
        let mut style = Style::default().fg(color);
        if !skill.enabled {
            style = style.add_modifier(Modifier::DIM);
        }

        let name_style = if is_cursor {
            Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD)
        } else if !skill.enabled {
            Style::default()
                .fg(Color::DarkGray)
                .add_modifier(Modifier::DIM)
        } else {
            Style::default().fg(Color::White)
        };

        let padded_name = format!("{:<width$}", skill.name, width = max_name_width);

        let mut spans = vec![
            Span::styled(
                format!("  {} ", cursor_char),
                if is_cursor {
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                },
            ),
            Span::styled(format!("[{}] ", badge), style),
            Span::styled(padded_name, name_style),
        ];

        // Right column: project aliases
        if let Some(label) = skill.mode.project_label() {
            spans.push(Span::styled(
                format!("  {}", label),
                Style::default().fg(Color::Cyan),
            ));
        }

        list_items.push(ListItem::new(Line::from(spans)));
        flat_idx += 1;

        // Scripts as indented children
        for script in &skill.scripts {
            let is_script_cursor = flat_idx == cursor_flat;
            let script_cursor = if is_script_cursor { "▶" } else { " " };

            let path_badge = if script.on_path { " [PATH]" } else { "" };

            let script_style = if !skill.enabled || !skill.mode.is_global() {
                Style::default()
                    .fg(Color::DarkGray)
                    .add_modifier(Modifier::DIM)
            } else if is_script_cursor {
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };

            let path_style = Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD);

            let line = Line::from(vec![
                Span::styled(
                    format!("  {} ", script_cursor),
                    if is_script_cursor {
                        Style::default()
                            .fg(Color::White)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    },
                ),
                Span::raw("          "), // indent past badge column
                Span::styled(&script.name, script_style),
                Span::styled(path_badge, path_style),
            ]);
            list_items.push(ListItem::new(line));
            flat_idx += 1;
        }
    }

    let list = List::new(list_items).block(Block::default().borders(Borders::NONE));
    frame.render_widget(list, area);
}

fn draw_simple_tab(frame: &mut Frame, app: &App, rows: &[super::app::SimpleRow], area: Rect) {
    let cursor_idx = app.cursors[app.active_tab];
    let mut list_items: Vec<ListItem> = Vec::new();

    // Compute max name width for column alignment
    let max_name_width = rows.iter().map(|r| r.name.len()).max().unwrap_or(0);

    for (idx, row) in rows.iter().enumerate() {
        let is_cursor = idx == cursor_idx;
        let color = if !row.enabled {
            Color::DarkGray
        } else {
            mode_color(&row.mode)
        };

        let cursor_char = if is_cursor { "▶" } else { " " };
        let badge = mode_badge(&row.mode);
        let mut style = Style::default().fg(color);
        if !row.enabled {
            style = style.add_modifier(Modifier::DIM);
        }

        let name_style = if is_cursor {
            Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD)
        } else if !row.enabled {
            Style::default()
                .fg(Color::DarkGray)
                .add_modifier(Modifier::DIM)
        } else {
            Style::default().fg(Color::White)
        };

        let padded_name = format!("{:<width$}", row.name, width = max_name_width);

        let mut spans = vec![
            Span::styled(
                format!("  {} ", cursor_char),
                if is_cursor {
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                },
            ),
            Span::styled(format!("[{}] ", badge), style),
            Span::styled(padded_name, name_style),
        ];

        // Right column: project aliases
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
        let cursor_char = if is_cursor { "▶" } else { " " };
        let path_display = project.path.to_string_lossy().replace(
            dirs::home_dir()
                .unwrap_or_default()
                .to_string_lossy()
                .as_ref(),
            "~",
        );

        let line = Line::from(vec![
            Span::styled(
                format!("  {} ", cursor_char),
                if is_cursor {
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                },
            ),
            Span::styled(format!("{}  ", idx + 1), Style::default().fg(Color::Cyan)),
            Span::styled(
                format!("{:<12} ", project.alias),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                path_display,
                if is_cursor {
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::White)
                },
            ),
        ]);

        list_items.push(ListItem::new(line));
    }

    let list = List::new(list_items).block(Block::default().borders(Borders::NONE));
    frame.render_widget(list, area);
}

fn draw_project_modal(frame: &mut Frame, app: &App, area: Rect) {
    let modal_height = (app.projects.len() as u16 + 4).min(area.height.saturating_sub(2));
    let modal_width = 50u16.min(area.width.saturating_sub(4));

    // Center the modal
    let x = area.x + (area.width.saturating_sub(modal_width)) / 2;
    let y = area.y + (area.height.saturating_sub(modal_height)) / 2;
    let modal_area = Rect::new(x, y, modal_width, modal_height);

    // Clear area behind modal
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

        let path_display = project.path.to_string_lossy().replace(
            dirs::home_dir()
                .unwrap_or_default()
                .to_string_lossy()
                .as_ref(),
            "~",
        );

        let style = if is_cursor {
            Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::White)
        };

        let cursor_char = if is_cursor { "▶" } else { " " };

        lines.push(Line::from(vec![
            Span::styled(format!(" {} ", cursor_char), style),
            Span::styled(format!("{} ", checkbox), Style::default().fg(Color::Cyan)),
            Span::styled(
                format!("{:<10} ", project.alias),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(path_display, style),
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
            } else if trimmed.starts_with("Deployed:") || trimmed.starts_with("Included:") {
                Line::from(Span::styled(s.as_str(), Style::default().fg(Color::Green)))
            } else if trimmed.starts_with('+') {
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
                    // Show O key hint if cursor is on a script
                    if let Some(SkillPos::Script(_, _)) = app.current_skill_pos() {
                        spans.extend_from_slice(&[
                            Span::styled("[O]", Style::default().fg(Color::Cyan)),
                            Span::raw(" path  "),
                        ]);
                    }
                    if !app.projects.is_empty() {
                        spans.extend_from_slice(&[
                            Span::styled("[P]", Style::default().fg(Color::Cyan)),
                            Span::raw(" projects  "),
                        ]);
                    }
                }
                TAB_HOOKS => {
                    spans.extend_from_slice(&[
                        Span::styled("[Space]", Style::default().fg(Color::Cyan)),
                        Span::raw(" cycle  "),
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
