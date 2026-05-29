use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Clear, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use super::app::{App, PendingAction};
use super::AppMode;

// Color palette
const BORDER_COLOR: Color = Color::Blue;
const TITLE_COLOR: Color = Color::Cyan;
const INPUT_COLOR: Color = Color::White;
const CURSOR_COLOR: Color = Color::Green;
const MATCH_COLOR: Color = Color::Yellow;
const SELECTED_BG: Color = Color::DarkGray;
const SELECTED_FG: Color = Color::White;
const COUNTER_COLOR: Color = Color::DarkGray;
const HELP_COLOR: Color = Color::DarkGray;
const POPUP_BORDER_COLOR: Color = Color::Magenta;
const POPUP_HIGHLIGHT_COLOR: Color = Color::Green;
const ACTION_NORMAL_COLOR: Color = Color::White;
const MESSAGE_SUCCESS_COLOR: Color = Color::Green;
const MESSAGE_ERROR_COLOR: Color = Color::Red;
const MODE_INSERT_COLOR: Color = Color::Green;
const MODE_NORMAL_COLOR: Color = Color::Yellow;
const ENTRY_COLOR: Color = Color::White;
const DISPLAY_TEXT_COLOR: Color = Color::White;

/// Main entry point for rendering.
pub fn draw(frame: &mut Frame, app: &mut App) {
    // Set black background for the entire frame
    let bg_block = Block::default().style(Style::default().bg(Color::Black));
    frame.render_widget(bg_block, frame.area());

    // Always draw the main layout (search + list + help)
    draw_main(frame, app);

    // Overlay popups
    if app.mode == AppMode::Action {
        draw_action_popup(frame, app);
    }
    if app.mode == AppMode::Display {
        draw_display_popup(frame, app);
    }
    if app.mode == AppMode::InputName {
        draw_name_input_popup(frame, app);
    }
}

/// Main layout: search bar, password list, help bar (no action bar row)
fn draw_main(frame: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // search input
            Constraint::Min(1),    // password list
            Constraint::Length(3), // help/status bar
        ])
        .split(frame.area());

    // --- Search input block ---
    let cursor_char = if app.mode == AppMode::Insert { "\u{2588}" } else { "" };
    let input_spans = vec![
        Span::styled("\u{276f} ", Style::default().fg(CURSOR_COLOR).add_modifier(Modifier::BOLD)),
        Span::styled(app.query.as_str(), Style::default().fg(INPUT_COLOR)),
        Span::styled(cursor_char, Style::default().fg(CURSOR_COLOR)),
    ];
    let input_line = Line::from(input_spans);

    let input_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(BORDER_COLOR))
        .title(Span::styled(
            " pars ",
            Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD),
        ))
        .title_alignment(Alignment::Left);

    let input_paragraph = Paragraph::new(input_line).block(input_block);
    frame.render_widget(input_paragraph, chunks[0]);

    // Mode indicator in top-right — ONLY in vim mode
    if app.vim_enabled {
        let mode_indicator = match app.mode {
            AppMode::Insert => Span::styled(
                " INSERT ",
                Style::default()
                    .fg(Color::Black)
                    .bg(MODE_INSERT_COLOR)
                    .add_modifier(Modifier::BOLD),
            ),
            AppMode::Normal => Span::styled(
                " NORMAL ",
                Style::default()
                    .fg(Color::Black)
                    .bg(MODE_NORMAL_COLOR)
                    .add_modifier(Modifier::BOLD),
            ),
            _ => Span::raw(""),
        };
        if mode_indicator.width() > 0 {
            let mode_width = mode_indicator.width() as u16 + 2;
            if chunks[0].width > mode_width + 8 {
                let mode_area = Rect {
                    x: chunks[0].x + chunks[0].width.saturating_sub(mode_width + 1),
                    y: chunks[0].y,
                    width: mode_width,
                    height: 1,
                };
                frame.render_widget(
                    Paragraph::new(Line::from(vec![
                        Span::raw(" "),
                        mode_indicator,
                        Span::raw(" "),
                    ])),
                    mode_area,
                );
            }
        }
    }

    // --- Password list ---
    let total = app.entries.len();
    let filtered_count = app.filtered.len();
    let counter = format!(" {}/{} ", filtered_count, total);

    let results_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(BORDER_COLOR))
        .title(Span::styled(counter, Style::default().fg(COUNTER_COLOR)));

    let inner_area = results_block.inner(chunks[1]);
    frame.render_widget(results_block, chunks[1]);

    if app.filtered.is_empty() {
        let no_matches = Paragraph::new(Line::from(Span::styled(
            "  No matches found",
            Style::default().fg(Color::DarkGray).add_modifier(Modifier::ITALIC),
        )));
        frame.render_widget(no_matches, inner_area);
    } else {
        let visible_height = inner_area.height as usize;
        app.visible_height = visible_height;

        if app.cursor >= app.scroll_offset + visible_height {
            app.scroll_offset = app.cursor.saturating_sub(visible_height.saturating_sub(1));
        }
        if app.cursor < app.scroll_offset {
            app.scroll_offset = app.cursor;
        }

        let visible_end = (app.scroll_offset + visible_height).min(filtered_count);
        let items: Vec<ListItem> = app
            .filtered
            .iter()
            .enumerate()
            .skip(app.scroll_offset)
            .take(visible_end - app.scroll_offset)
            .map(|(i, entry)| {
                let is_selected = i == app.cursor;
                let line = highlight_matches(&entry.0, &entry.1, is_selected);
                if is_selected {
                    ListItem::new(line).style(Style::default().bg(SELECTED_BG))
                } else {
                    ListItem::new(line)
                }
            })
            .collect();

        let list = List::new(items);
        frame.render_widget(list, inner_area);
    }

    // --- Help/Status bar ---
    let help_spans = if app.vim_enabled {
        match app.mode {
            AppMode::Insert => vec![
                styled_key("Esc"),
                styled_help(" normal  "),
                styled_key("\u{2191}\u{2193}"),
                styled_help(" navigate  "),
                styled_key("Enter"),
                styled_help(" select  "),
                styled_key("Ctrl-G"),
                styled_help(" generate  "),
                styled_key("Ctrl-N"),
                styled_help(" insert  "),
                styled_key("Ctrl-C"),
                styled_help(" quit"),
            ],
            AppMode::Normal => vec![
                styled_key("i"),
                styled_help(" insert  "),
                styled_key("j/k"),
                styled_help(" navigate  "),
                styled_key("Ctrl-G"),
                styled_help(" generate  "),
                styled_key("Ctrl-N"),
                styled_help(" insert  "),
                styled_key("Enter"),
                styled_help(" select  "),
                styled_key("q"),
                styled_help(" quit"),
            ],
            _ => vec![],
        }
    } else {
        vec![
            styled_key("\u{2191}\u{2193}"),
            styled_help(" navigate  "),
            styled_key("Enter"),
            styled_help(" select  "),
            styled_key("Ctrl-G"),
            styled_help(" generate  "),
            styled_key("Ctrl-N"),
            styled_help(" insert  "),
            styled_key("Esc"),
            styled_help(" quit"),
        ]
    };

    let status_content = if let Some(ref msg) = app.message {
        let color = if msg.contains("error") || msg.contains("Error") || msg.contains("failed") {
            MESSAGE_ERROR_COLOR
        } else {
            MESSAGE_SUCCESS_COLOR
        };
        Line::from(Span::styled(
            format!("  {msg}"),
            Style::default().fg(color).add_modifier(Modifier::BOLD),
        ))
    } else {
        Line::from(help_spans)
    };

    let status_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(BORDER_COLOR));

    let status_paragraph = Paragraph::new(status_content).block(status_block);
    frame.render_widget(status_paragraph, chunks[2]);
}

fn styled_key(s: &str) -> Span<'_> {
    Span::styled(s, Style::default().fg(Color::White).add_modifier(Modifier::BOLD))
}

fn styled_help(s: &str) -> Span<'_> {
    Span::styled(s, Style::default().fg(HELP_COLOR))
}

/// Render the action popup (after selecting an existing password).
fn draw_action_popup(frame: &mut Frame, app: &App) {
    let area = frame.area();

    let popup_width = 70u16.min(area.width.saturating_sub(4));
    let popup_height = 14u16.min(area.height.saturating_sub(4));

    // Layout: input(3) + results_border(1) = 4 rows before list
    let results_start_y: u16 = 4;
    let visible_cursor = app.cursor.saturating_sub(app.scroll_offset) as u16;
    let selected_row_y = results_start_y + visible_cursor;
    let screen_center_y = area.height / 2;

    let popup_y = if selected_row_y < screen_center_y {
        (selected_row_y + 1).min(area.height.saturating_sub(popup_height))
    } else {
        selected_row_y.saturating_sub(popup_height)
    };
    let popup_y = popup_y.min(area.height.saturating_sub(popup_height));
    let popup_x = (area.width.saturating_sub(popup_width)) / 2;

    let popup_area = Rect { x: popup_x, y: popup_y, width: popup_width, height: popup_height };

    frame.render_widget(Clear, popup_area);

    let selected = app.selected_entry.as_deref().unwrap_or("?");
    let title = format!(" {} ", selected);

    let popup_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Double)
        .border_style(Style::default().fg(POPUP_BORDER_COLOR).bg(Color::Black))
        .title(Span::styled(title, Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)))
        .title_alignment(Alignment::Center);

    // If a confirmation is pending, replace the action list with a clear yes/no prompt.
    if let Some(ref prompt) = app.confirm_prompt {
        let mut lines: Vec<Line> = vec![
            Line::from(""),
            Line::from(Span::styled(
                format!("  {}", prompt),
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from(vec![
                Span::raw("    "),
                Span::styled(
                    " y ",
                    Style::default().fg(Color::Black).bg(Color::Green).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" yes      ", Style::default().fg(ACTION_NORMAL_COLOR)),
                Span::styled(
                    " n ",
                    Style::default().fg(Color::Black).bg(Color::Red).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" no", Style::default().fg(ACTION_NORMAL_COLOR)),
            ]),
            Line::from(""),
            Line::from(vec![Span::raw("  "), styled_key("Esc"), styled_help(" cancel")]),
        ];
        if let Some(ref msg) = app.message {
            lines.push(Line::from(""));
            lines.push(Line::from(Span::styled(
                format!("  {msg}"),
                Style::default().fg(MESSAGE_ERROR_COLOR),
            )));
        }
        let paragraph =
            Paragraph::new(lines).style(Style::default().bg(Color::Black)).block(popup_block);
        frame.render_widget(paragraph, popup_area);
        return;
    }

    let actions = [
        "[c] Copy to clipboard",
        "[d] Display password",
        "[r] Show as QR code",
        "[e] Edit password",
        "[g] Regenerate password",
    ];

    let mut lines: Vec<Line> = vec![Line::from("")];

    for (i, label) in actions.iter().enumerate() {
        let is_active = i == app.action_cursor;
        let style = if is_active {
            Style::default().fg(Color::Black).bg(POPUP_HIGHLIGHT_COLOR).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(ACTION_NORMAL_COLOR)
        };
        let prefix = if is_active { " \u{25b6} " } else { "   " };
        lines.push(Line::from(vec![Span::styled(prefix, style), Span::styled(*label, style)]));
    }

    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::raw("   "),
        styled_key("Esc"),
        styled_help(" back  "),
        styled_key("q"),
        styled_help(" quit"),
    ]));

    if let Some(ref msg) = app.message {
        let color = if msg.contains("error") || msg.contains("Error") {
            MESSAGE_ERROR_COLOR
        } else {
            MESSAGE_SUCCESS_COLOR
        };
        lines.push(Line::from(Span::styled(format!("   {msg}"), Style::default().fg(color))));
    }

    let paragraph =
        Paragraph::new(lines).style(Style::default().bg(Color::Black)).block(popup_block);
    frame.render_widget(paragraph, popup_area);
}

/// Display mode: centered popup showing decrypted content.
fn draw_display_popup(frame: &mut Frame, app: &App) {
    let area = frame.area();

    let popup_width = (area.width.saturating_sub(6)).min(80);
    let popup_height = (area.height.saturating_sub(6)).min(area.height.saturating_sub(4));

    let popup_x = (area.width.saturating_sub(popup_width)) / 2;
    let popup_y = (area.height.saturating_sub(popup_height)) / 2;

    let popup_area = Rect { x: popup_x, y: popup_y, width: popup_width, height: popup_height };

    frame.render_widget(Clear, popup_area);

    let selected = app.selected_entry.as_deref().unwrap_or("?");
    let title = format!(" {} ", selected);
    let content = app.decrypted_content.as_deref().unwrap_or("");

    let inner_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(1)])
        .split(popup_area);

    let content_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Double)
        .border_style(Style::default().fg(TITLE_COLOR).bg(Color::Black))
        .title(Span::styled(title, Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)))
        .title_alignment(Alignment::Center);

    let content_paragraph = Paragraph::new(content)
        .style(Style::default().fg(DISPLAY_TEXT_COLOR).bg(Color::Black))
        .block(content_block)
        .wrap(Wrap { trim: false });
    frame.render_widget(content_paragraph, inner_chunks[0]);

    let help_line = Line::from(vec![Span::styled(
        " Press any key to go back ",
        Style::default().fg(HELP_COLOR).bg(Color::Black),
    )]);
    frame.render_widget(
        Paragraph::new(help_line)
            .style(Style::default().bg(Color::Black))
            .alignment(Alignment::Center),
        inner_chunks[1],
    );
}

/// Centered popup for entering a new entry name (Generate / Insert).
fn draw_name_input_popup(frame: &mut Frame, app: &App) {
    let area = frame.area();

    let popup_width = 60u16.min(area.width.saturating_sub(4));
    let popup_height = 6u16.min(area.height.saturating_sub(4));

    let popup_x = (area.width.saturating_sub(popup_width)) / 2;
    let popup_y = (area.height.saturating_sub(popup_height)) / 2;

    let popup_area = Rect { x: popup_x, y: popup_y, width: popup_width, height: popup_height };

    frame.render_widget(Clear, popup_area);

    let title = match app.pending_action {
        Some(PendingAction::Generate) => " Generate new password ",
        Some(PendingAction::Insert) => " Insert new password ",
        None => " New entry ",
    };

    let popup_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Double)
        .border_style(Style::default().fg(POPUP_BORDER_COLOR).bg(Color::Black))
        .title(Span::styled(title, Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)))
        .title_alignment(Alignment::Center);

    let inner = popup_block.inner(popup_area);
    frame.render_widget(popup_block, popup_area);

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1), // spacer
            Constraint::Length(1), // input line
            Constraint::Length(1), // spacer
            Constraint::Length(1), // help / message
        ])
        .split(inner);

    // Input line: "Name: <typed>_"
    let input_line = Line::from(vec![
        Span::styled("  Name: ", Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)),
        Span::styled(app.name_input.as_str(), Style::default().fg(INPUT_COLOR)),
        Span::styled("\u{2588}", Style::default().fg(CURSOR_COLOR).add_modifier(Modifier::BOLD)),
    ]);
    frame.render_widget(
        Paragraph::new(input_line).style(Style::default().bg(Color::Black)),
        chunks[1],
    );

    // Help / message line
    let help_or_msg = if let Some(ref msg) = app.message {
        let color = if msg.contains("error") || msg.contains("Error") || msg.contains("empty") {
            MESSAGE_ERROR_COLOR
        } else {
            MESSAGE_SUCCESS_COLOR
        };
        Line::from(Span::styled(
            format!("  {msg}"),
            Style::default().fg(color).add_modifier(Modifier::BOLD),
        ))
    } else {
        Line::from(vec![
            Span::raw("  "),
            styled_key("Enter"),
            styled_help(" confirm   "),
            styled_key("Esc"),
            styled_help(" cancel   "),
            styled_key("Ctrl-U"),
            styled_help(" clear"),
        ])
    };
    frame.render_widget(
        Paragraph::new(help_or_msg).style(Style::default().bg(Color::Black)),
        chunks[3],
    );
}

/// Highlight matched characters in `entry` using the explicit list of matched character indices
/// (as computed by the fuzzy matcher in `filter_entries`). Char indices, not byte indices.
fn highlight_matches(entry: &str, indices: &[u32], is_selected: bool) -> Line<'static> {
    let prefix = if is_selected {
        Span::styled(" \u{25b6} ", Style::default().fg(CURSOR_COLOR).add_modifier(Modifier::BOLD))
    } else {
        Span::styled("   ", Style::default())
    };

    let mut spans: Vec<Span<'static>> = vec![prefix];

    let base_style = if is_selected {
        Style::default().fg(SELECTED_FG).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(ENTRY_COLOR)
    };

    let match_style = Style::default().fg(MATCH_COLOR).add_modifier(Modifier::BOLD);

    if indices.is_empty() {
        spans.push(Span::styled(entry.to_string(), base_style));
        return Line::from(spans);
    }

    // Build runs of consecutive char indices so they get a single styled span.
    let mut current_run = String::new();
    let mut current_is_match = false;

    for (i, ch) in entry.chars().enumerate() {
        let is_match = indices.binary_search(&(i as u32)).is_ok();

        if is_match != current_is_match && !current_run.is_empty() {
            let style = if current_is_match { match_style } else { base_style };
            spans.push(Span::styled(std::mem::take(&mut current_run), style));
        }
        current_is_match = is_match;
        current_run.push(ch);
    }

    if !current_run.is_empty() {
        let style = if current_is_match { match_style } else { base_style };
        spans.push(Span::styled(current_run, style));
    }

    Line::from(spans)
}
