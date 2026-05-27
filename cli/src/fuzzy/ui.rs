use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Clear, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use super::{App, AppMode};

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
    // Set black background for the entire frame (ensures readability on light terminals)
    let bg_block = Block::default().style(Style::default().bg(Color::Black));
    frame.render_widget(bg_block, frame.area());

    // Always draw the search background
    draw_search(frame, app);

    // Overlay popup for Action mode
    if app.mode == AppMode::Action {
        draw_action_popup(frame, app);
    }

    // Full-screen display mode
    if app.mode == AppMode::Display {
        draw_display(frame, app);
    }
}

/// Render the search mode: input box, filtered results list, and help bar.
fn draw_search(frame: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // input
            Constraint::Min(1),    // results
            Constraint::Length(3), // help/status
        ])
        .split(frame.area());

    // --- Input block ---
    let mode_indicator = match app.mode {
        AppMode::Insert => Span::styled(
            " INSERT ",
            Style::default().fg(Color::Black).bg(MODE_INSERT_COLOR).add_modifier(Modifier::BOLD),
        ),
        AppMode::Normal => Span::styled(
            " NORMAL ",
            Style::default().fg(Color::Black).bg(MODE_NORMAL_COLOR).add_modifier(Modifier::BOLD),
        ),
        AppMode::Action => Span::styled(
            " ACTION ",
            Style::default().fg(Color::Black).bg(POPUP_BORDER_COLOR).add_modifier(Modifier::BOLD),
        ),
        AppMode::Display => Span::styled(
            " DISPLAY ",
            Style::default().fg(Color::Black).bg(TITLE_COLOR).add_modifier(Modifier::BOLD),
        ),
    };

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

    // Render mode indicator in top-right of input block
    let mode_area = Rect {
        x: chunks[0].x + chunks[0].width.saturating_sub(mode_indicator.width() as u16 + 2),
        y: chunks[0].y,
        width: mode_indicator.width() as u16 + 2,
        height: 1,
    };
    frame.render_widget(
        Paragraph::new(Line::from(vec![Span::raw(" "), mode_indicator, Span::raw(" ")])),
        mode_area,
    );

    // --- Results block ---
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

        // Adjust scroll offset to keep cursor visible
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
                let line = highlight_matches(&entry.0, &app.query, is_selected);
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
                Span::styled("Esc", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Span::styled(" normal  ", Style::default().fg(HELP_COLOR)),
                Span::styled(
                    "\u{2191}\u{2193}",
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" navigate  ", Style::default().fg(HELP_COLOR)),
                Span::styled(
                    "Enter",
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" select  ", Style::default().fg(HELP_COLOR)),
                Span::styled(
                    "Ctrl-C",
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" quit", Style::default().fg(HELP_COLOR)),
            ],
            AppMode::Normal => vec![
                Span::styled("i", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Span::styled(" insert  ", Style::default().fg(HELP_COLOR)),
                Span::styled("j/k", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Span::styled(" navigate  ", Style::default().fg(HELP_COLOR)),
                Span::styled("g/G", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Span::styled(" top/bottom  ", Style::default().fg(HELP_COLOR)),
                Span::styled(
                    "Enter",
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" select  ", Style::default().fg(HELP_COLOR)),
                Span::styled("q", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Span::styled(" quit", Style::default().fg(HELP_COLOR)),
            ],
            _ => vec![],
        }
    } else {
        vec![
            Span::styled(
                "\u{2191}\u{2193}",
                Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
            ),
            Span::styled(" navigate  ", Style::default().fg(HELP_COLOR)),
            Span::styled("Enter", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
            Span::styled(" select  ", Style::default().fg(HELP_COLOR)),
            Span::styled("Esc", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
            Span::styled(" quit", Style::default().fg(HELP_COLOR)),
        ]
    };

    // Show message if present, otherwise show help
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

/// Render the action popup as an overlay on top of the search screen.
fn draw_action_popup(frame: &mut Frame, app: &App) {
    let area = frame.area();

    // Popup dimensions
    let popup_width = 44u16.min(area.width.saturating_sub(4));
    let popup_height = 12u16.min(area.height.saturating_sub(4));

    // Calculate the screen row of the selected entry.
    // Layout: input block (3 rows) + results top border (1 row) = 4 rows before list items
    let results_start_y: u16 = 4;
    let visible_cursor = app.cursor.saturating_sub(app.scroll_offset) as u16;
    let selected_row_y = results_start_y + visible_cursor;

    // Screen center
    let screen_center_y = area.height / 2;

    // Determine popup Y position:
    // If selected row is in upper half -> popup top edge aligns with selected row (opens downward)
    // If selected row is in lower half -> popup bottom edge aligns with selected row (opens upward)
    let popup_y = if selected_row_y < screen_center_y {
        // Upper half: top edge at selected row + 1 (just below the selected item)
        (selected_row_y + 1).min(area.height.saturating_sub(popup_height))
    } else {
        // Lower half: bottom edge at selected row (popup above the item)
        selected_row_y.saturating_sub(popup_height)
    };

    // Clamp to screen bounds
    let popup_y = popup_y.max(0).min(area.height.saturating_sub(popup_height));

    // Center horizontally
    let popup_x = (area.width.saturating_sub(popup_width)) / 2;

    let popup_area = Rect { x: popup_x, y: popup_y, width: popup_width, height: popup_height };

    // Clear the area behind the popup
    frame.render_widget(Clear, popup_area);

    let selected = app.selected_entry.as_deref().unwrap_or("?");
    let title = format!(" {} ", selected);

    let popup_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Double)
        .border_style(Style::default().fg(POPUP_BORDER_COLOR).bg(Color::Black))
        .title(Span::styled(title, Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)))
        .title_alignment(Alignment::Center);

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
        Span::styled("   ", Style::default()),
        Span::styled("Esc", Style::default().fg(HELP_COLOR).add_modifier(Modifier::BOLD)),
        Span::styled(" back  ", Style::default().fg(HELP_COLOR)),
        Span::styled("q", Style::default().fg(HELP_COLOR).add_modifier(Modifier::BOLD)),
        Span::styled(" quit", Style::default().fg(HELP_COLOR)),
    ]));

    // Show message if present
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

/// Render the display mode showing decrypted content.
fn draw_display(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(1),    // content
            Constraint::Length(3), // help
        ])
        .split(frame.area());

    let selected = app.selected_entry.as_deref().unwrap_or("?");
    let title = format!(" {} ", selected);
    let content = app.decrypted_content.as_deref().unwrap_or("");

    let content_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(BORDER_COLOR))
        .title(Span::styled(title, Style::default().fg(TITLE_COLOR).add_modifier(Modifier::BOLD)));

    let content_paragraph = Paragraph::new(content)
        .style(Style::default().fg(DISPLAY_TEXT_COLOR))
        .block(content_block)
        .wrap(Wrap { trim: false });
    frame.render_widget(content_paragraph, chunks[0]);

    let help_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(BORDER_COLOR));

    let help_text = Paragraph::new(Line::from(vec![
        Span::styled("  Press ", Style::default().fg(HELP_COLOR)),
        Span::styled("any key", Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        Span::styled(" to go back", Style::default().fg(HELP_COLOR)),
    ]))
    .block(help_block);
    frame.render_widget(help_text, chunks[1]);
}

/// Highlight characters in `entry` that match the fuzzy query as a subsequence.
fn highlight_matches<'a>(entry: &'a str, query: &str, is_selected: bool) -> Line<'a> {
    let prefix = if is_selected {
        Span::styled(" \u{25b6} ", Style::default().fg(CURSOR_COLOR).add_modifier(Modifier::BOLD))
    } else {
        Span::styled("   ", Style::default())
    };

    let mut spans: Vec<Span<'a>> = vec![prefix];

    let base_style = if is_selected {
        Style::default().fg(SELECTED_FG).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(ENTRY_COLOR)
    };

    let match_style = Style::default().fg(MATCH_COLOR).add_modifier(Modifier::BOLD);

    if query.is_empty() {
        spans.push(Span::styled(entry, base_style));
        return Line::from(spans);
    }

    let mut query_chars = query.chars().peekable();
    let mut current_run = String::new();
    let mut current_is_match = false;

    for ch in entry.chars() {
        let matches_query =
            query_chars.peek().map(|qc| qc.eq_ignore_ascii_case(&ch)).unwrap_or(false);

        if matches_query {
            if !current_is_match && !current_run.is_empty() {
                spans.push(Span::styled(current_run.clone(), base_style));
                current_run.clear();
            }
            current_is_match = true;
            current_run.push(ch);
            query_chars.next();
        } else {
            if current_is_match && !current_run.is_empty() {
                spans.push(Span::styled(current_run.clone(), match_style));
                current_run.clear();
            }
            current_is_match = false;
            current_run.push(ch);
        }
    }

    if !current_run.is_empty() {
        let style = if current_is_match { match_style } else { base_style };
        spans.push(Span::styled(current_run, style));
    }

    Line::from(spans)
}
