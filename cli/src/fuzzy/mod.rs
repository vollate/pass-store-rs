pub mod ui;

use std::path::Path;
use std::{fs, io};

use anyhow::{anyhow, Error, Result};
use crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers, MouseEventKind,
};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use fast_qr::QRBuilder;
use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config, Matcher, Utf32Str};
use pars_core::clipboard::copy_to_clipboard;
use pars_core::config::cli::ParsConfig;
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::util::tree::{FilterType, TreeConfig, TreePrintConfig};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;
use secrecy::{ExposeSecret, SecretString};

use crate::util::unwrap_root_path;

#[derive(PartialEq, Clone, Copy)]
pub enum AppMode {
    /// Insert mode: typing filters entries (like fzf)
    Insert,
    /// Normal mode (vim): navigate with j/k, no typing into query
    Normal,
    /// Action popup: choose what to do with the selected password
    Action,
    /// Display: show decrypted content or QR
    Display,
}

pub struct App {
    pub query: String,
    pub entries: Vec<String>,
    pub filtered: Vec<(String, u32)>,
    pub cursor: usize,
    pub scroll_offset: usize,
    pub mode: AppMode,
    pub vim_enabled: bool,
    pub selected_entry: Option<String>,
    pub decrypted_content: Option<String>,
    pub message: Option<String>,
    pub action_cursor: usize,
    pub visible_height: usize,
    pub pending_d: bool, // For tracking 'd' in "dd" sequence
}

impl App {
    pub fn new(entries: Vec<String>, vim_enabled: bool) -> Self {
        let filtered: Vec<(String, u32)> = entries.iter().map(|e| (e.clone(), 0)).collect();
        Self {
            query: String::new(),
            entries,
            filtered,
            cursor: 0,
            scroll_offset: 0,
            mode: AppMode::Insert,
            vim_enabled,
            selected_entry: None,
            decrypted_content: None,
            message: None,
            action_cursor: 0,
            visible_height: 0,
            pending_d: false,
        }
    }

    /// Whether the search mode is active (Insert or Normal)
    #[allow(dead_code)]
    pub fn is_searching(&self) -> bool {
        matches!(self.mode, AppMode::Insert | AppMode::Normal)
    }
}

fn collect_entries(root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    collect_entries_recursive(root, root, &mut entries);
    entries.sort();
    entries
}

fn collect_entries_recursive(root: &Path, current: &Path, entries: &mut Vec<String>) {
    let Ok(read_dir) = fs::read_dir(current) else {
        return;
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        let file_name = entry.file_name().to_string_lossy().to_string();

        if file_name.starts_with('.') {
            continue;
        }

        if path.is_dir() {
            collect_entries_recursive(root, &path, entries);
        } else if file_name.ends_with(".gpg") && file_name != ".gpg-id" {
            if let Ok(relative) = path.strip_prefix(root) {
                let rel_str = relative.to_string_lossy();
                let entry_name = rel_str.trim_end_matches(".gpg").to_string();
                entries.push(entry_name);
            }
        }
    }
}

pub fn filter_entries(
    query: &str,
    entries: &[String],
    matcher: &mut Matcher,
) -> Vec<(String, u32)> {
    if query.is_empty() {
        return entries.iter().map(|e| (e.clone(), 0)).collect();
    }

    let pattern = Pattern::parse(query, CaseMatching::Smart, Normalization::Smart);
    let mut buf = Vec::new();
    let mut results: Vec<(String, u32)> = entries
        .iter()
        .filter_map(|entry| {
            let haystack = Utf32Str::new(entry, &mut buf);
            pattern.score(haystack, matcher).map(|score| (entry.clone(), score))
        })
        .collect();

    results.sort_by(|a, b| b.1.cmp(&a.1));
    results
}

pub fn interactive_search(config: &ParsConfig, base_dir: Option<&str>) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let entries = collect_entries(&root);

    if entries.is_empty() {
        eprintln!("Password store is empty.");
        return Ok(());
    }

    // Setup terminal
    enable_raw_mode().map_err(|e| (1, anyhow!("Failed to enable raw mode: {e}")))?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)
        .map_err(|e| (1, anyhow!("Failed to enter alternate screen: {e}")))?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal =
        Terminal::new(backend).map_err(|e| (1, anyhow!("Failed to create terminal: {e}")))?;

    let vim_enabled = config.feature_config.vim_mode;
    let mut app = App::new(entries, vim_enabled);
    let result = run_app(&mut terminal, &mut app, config, base_dir);

    // Restore terminal
    disable_raw_mode().ok();
    execute!(terminal.backend_mut(), LeaveAlternateScreen, DisableMouseCapture).ok();
    terminal.show_cursor().ok();

    result
}

fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    config: &ParsConfig,
    base_dir: Option<&str>,
) -> Result<(), (i32, Error)> {
    let mut matcher = Matcher::new(Config::DEFAULT);
    let root = unwrap_root_path(base_dir, config);

    loop {
        terminal.draw(|frame| ui::draw(frame, app)).map_err(|e| (1, anyhow!("Draw error: {e}")))?;

        if event::poll(std::time::Duration::from_millis(200))
            .map_err(|e| (1, anyhow!("Event poll error: {e}")))?
        {
            let evt = event::read().map_err(|e| (1, anyhow!("Event read error: {e}")))?;

            // Clear transient messages on any input
            if app.message.is_some() {
                app.message = None;
            }

            match app.mode {
                AppMode::Insert => match evt {
                    Event::Key(key) => match key.code {
                        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            return Ok(());
                        }
                        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            // Ctrl-U: clear input
                            app.query.clear();
                            app.filtered = filter_entries(&app.query, &app.entries, &mut matcher);
                            app.cursor = 0;
                            app.scroll_offset = 0;
                        }
                        KeyCode::Char('w') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            // Ctrl-W: delete last word
                            let trimmed = app.query.trim_end();
                            if let Some(pos) = trimmed.rfind(|c: char| c == '/' || c == ' ') {
                                app.query.truncate(pos);
                            } else {
                                app.query.clear();
                            }
                            app.filtered = filter_entries(&app.query, &app.entries, &mut matcher);
                            app.cursor = 0;
                            app.scroll_offset = 0;
                        }
                        KeyCode::Esc => {
                            if app.vim_enabled {
                                app.mode = AppMode::Normal;
                            } else {
                                return Ok(());
                            }
                        }
                        KeyCode::Char(c) => {
                            app.query.push(c);
                            app.filtered = filter_entries(&app.query, &app.entries, &mut matcher);
                            app.cursor = 0;
                            app.scroll_offset = 0;
                        }
                        KeyCode::Backspace => {
                            app.query.pop();
                            app.filtered = filter_entries(&app.query, &app.entries, &mut matcher);
                            app.cursor = 0;
                            app.scroll_offset = 0;
                        }
                        KeyCode::Up => {
                            if app.cursor > 0 {
                                app.cursor -= 1;
                            }
                        }
                        KeyCode::Down => {
                            if !app.filtered.is_empty() && app.cursor < app.filtered.len() - 1 {
                                app.cursor += 1;
                            }
                        }
                        KeyCode::Enter => {
                            handle_select(app, config, &root)?;
                        }
                        _ => {}
                    },
                    Event::Mouse(mouse) => handle_mouse(app, mouse),
                    _ => {}
                },

                AppMode::Normal => match evt {
                    Event::Key(key) => {
                        // Handle Ctrl combinations first
                        if key.modifiers.contains(KeyModifiers::CONTROL) {
                            match key.code {
                                KeyCode::Char('c') => return Ok(()),
                                KeyCode::Char('d') => {
                                    // Ctrl-D: half page down
                                    let half = app.visible_height / 2;
                                    let max = app.filtered.len().saturating_sub(1);
                                    app.cursor = (app.cursor + half).min(max);
                                }
                                KeyCode::Char('u') => {
                                    // Ctrl-U: half page up
                                    let half = app.visible_height / 2;
                                    app.cursor = app.cursor.saturating_sub(half);
                                }
                                KeyCode::Char('f') => {
                                    // Ctrl-F: full page down
                                    let max = app.filtered.len().saturating_sub(1);
                                    app.cursor = (app.cursor + app.visible_height).min(max);
                                }
                                KeyCode::Char('b') => {
                                    // Ctrl-B: full page up
                                    app.cursor = app.cursor.saturating_sub(app.visible_height);
                                }
                                _ => {}
                            }
                            app.pending_d = false;
                        } else {
                            match key.code {
                                KeyCode::Char('q') => return Ok(()),
                                KeyCode::Char('i') => {
                                    app.mode = AppMode::Insert;
                                    app.pending_d = false;
                                }
                                KeyCode::Char('j') | KeyCode::Down => {
                                    if !app.filtered.is_empty()
                                        && app.cursor < app.filtered.len() - 1
                                    {
                                        app.cursor += 1;
                                    }
                                    app.pending_d = false;
                                }
                                KeyCode::Char('k') | KeyCode::Up => {
                                    if app.cursor > 0 {
                                        app.cursor -= 1;
                                    }
                                    app.pending_d = false;
                                }
                                KeyCode::Char('d') => {
                                    if app.pending_d {
                                        // dd: clear input
                                        app.query.clear();
                                        app.filtered =
                                            filter_entries(&app.query, &app.entries, &mut matcher);
                                        app.cursor = 0;
                                        app.scroll_offset = 0;
                                        app.pending_d = false;
                                    } else {
                                        app.pending_d = true;
                                    }
                                }
                                KeyCode::Char('D') => {
                                    // D: clear input (like dd but single key)
                                    app.query.clear();
                                    app.filtered =
                                        filter_entries(&app.query, &app.entries, &mut matcher);
                                    app.cursor = 0;
                                    app.scroll_offset = 0;
                                    app.pending_d = false;
                                }
                                KeyCode::Char('g') => {
                                    app.cursor = 0;
                                    app.pending_d = false;
                                }
                                KeyCode::Char('G') => {
                                    if !app.filtered.is_empty() {
                                        app.cursor = app.filtered.len() - 1;
                                    }
                                    app.pending_d = false;
                                }
                                KeyCode::Enter => {
                                    app.pending_d = false;
                                    handle_select(app, config, &root)?;
                                }
                                _ => {
                                    app.pending_d = false;
                                }
                            }
                        }
                    }
                    Event::Mouse(mouse) => {
                        app.pending_d = false;
                        handle_mouse(app, mouse);
                    }
                    _ => {}
                },

                AppMode::Action => {
                    if let Event::Key(key) = evt {
                        match key.code {
                            KeyCode::Char('1') | KeyCode::Char('c') => {
                                if do_copy(app, config)? {
                                    return Ok(());
                                }
                            }
                            KeyCode::Char('2') | KeyCode::Char('d') => {
                                app.mode = AppMode::Display;
                            }
                            KeyCode::Char('3') | KeyCode::Char('r') => {
                                do_qr(app)?;
                            }
                            KeyCode::Char('4') | KeyCode::Char('e') => {
                                do_edit(app, config, &root, terminal)?;
                                // After editing, re-decrypt to refresh
                                re_decrypt(app, config, &root);
                            }
                            KeyCode::Char('5') | KeyCode::Char('g') => {
                                do_generate(app, config, &root, terminal)?;
                            }
                            KeyCode::Esc | KeyCode::Char('b') => {
                                app.selected_entry = None;
                                app.decrypted_content = None;
                                app.action_cursor = 0;
                                if app.vim_enabled {
                                    app.mode = AppMode::Normal;
                                } else {
                                    app.mode = AppMode::Insert;
                                }
                                // Force full redraw to clear popup remnants
                                terminal.clear().map_err(|e| (1, anyhow!("Clear error: {e}")))?;
                            }
                            KeyCode::Char('q') => return Ok(()),
                            KeyCode::Up | KeyCode::Char('k') => {
                                if app.action_cursor > 0 {
                                    app.action_cursor -= 1;
                                }
                            }
                            KeyCode::Down | KeyCode::Char('j') => {
                                if app.action_cursor < 4 {
                                    app.action_cursor += 1;
                                }
                            }
                            KeyCode::Enter => match app.action_cursor {
                                0 => {
                                    if do_copy(app, config)? {
                                        return Ok(());
                                    }
                                }
                                1 => app.mode = AppMode::Display,
                                2 => do_qr(app)?,
                                3 => {
                                    do_edit(app, config, &root, terminal)?;
                                    re_decrypt(app, config, &root);
                                }
                                4 => do_generate(app, config, &root, terminal)?,
                                _ => {}
                            },
                            _ => {}
                        }
                    }
                }

                AppMode::Display => {
                    if let Event::Key(_) = evt {
                        // Re-decrypt to restore original content (in case QR replaced it)
                        if let Some(ref entry_name) = app.selected_entry {
                            let tree_cfg = TreeConfig {
                                root: &root,
                                target: entry_name,
                                filter_type: FilterType::Disable,
                                filters: Vec::new(),
                            };
                            let print_cfg = TreePrintConfig {
                                dir_color: None,
                                file_color: None,
                                symbol_color: None,
                                tree_color: None,
                            };
                            if let Ok(LsOrShow::Password(secret)) = ls_io(
                                &config.executable_config.pgp_executable,
                                &tree_cfg,
                                &print_cfg,
                            ) {
                                app.decrypted_content = Some(secret.expose_secret().to_string());
                            }
                        }
                        app.mode = AppMode::Action;
                    }
                }
            }
        }
    }
}

fn handle_select(app: &mut App, config: &ParsConfig, root: &Path) -> Result<(), (i32, Error)> {
    if app.filtered.is_empty() {
        return Ok(());
    }

    let entry_name = app.filtered[app.cursor].0.clone();
    let tree_cfg = TreeConfig {
        root,
        target: &entry_name,
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    let print_cfg =
        TreePrintConfig { dir_color: None, file_color: None, symbol_color: None, tree_color: None };

    match ls_io(&config.executable_config.pgp_executable, &tree_cfg, &print_cfg) {
        Ok(LsOrShow::Password(secret)) => {
            app.decrypted_content = Some(secret.expose_secret().to_string());
            app.selected_entry = Some(entry_name);
            app.action_cursor = 0;
            app.mode = AppMode::Action;
        }
        Ok(LsOrShow::DirTree(_)) => {
            app.message = Some("Selected item is a directory".to_string());
        }
        Err(e) => {
            app.message = Some(format!("Decryption failed: {e}"));
        }
    }
    Ok(())
}

fn handle_mouse(app: &mut App, mouse: event::MouseEvent) {
    match mouse.kind {
        MouseEventKind::ScrollUp => {
            if app.cursor > 0 {
                app.cursor -= 1;
            }
        }
        MouseEventKind::ScrollDown => {
            if !app.filtered.is_empty() && app.cursor < app.filtered.len() - 1 {
                app.cursor += 1;
            }
        }
        MouseEventKind::Down(event::MouseButton::Left) => {
            // Calculate which row was clicked
            // Layout: input block (3 rows) + results top border (1 row) = 4 rows before list items
            let results_start_y: u16 = 4;
            let click_y = mouse.row;
            if click_y >= results_start_y {
                let clicked_offset = (click_y - results_start_y) as usize;
                let target_index = app.scroll_offset + clicked_offset;
                if target_index < app.filtered.len() {
                    app.cursor = target_index;
                }
            }
        }
        _ => {}
    }
}

fn do_copy(app: &mut App, config: &ParsConfig) -> Result<bool, (i32, Error)> {
    if let Some(ref content) = app.decrypted_content {
        let first_line = content.lines().next().unwrap_or("").to_string();
        let secret: SecretString = first_line.into();
        match copy_to_clipboard(secret, &config.feature_config.clip_time) {
            Ok(_) => {
                app.message = Some("Copied to clipboard!".to_string());
                if config.feature_config.exit_on_copy {
                    return Ok(true); // Signal exit
                }
                // Go back to search
                app.selected_entry = None;
                app.decrypted_content = None;
                app.action_cursor = 0;
                if app.vim_enabled {
                    app.mode = AppMode::Normal;
                } else {
                    app.mode = AppMode::Insert;
                }
            }
            Err(e) => {
                app.message = Some(format!("Clipboard error: {e}"));
            }
        }
    }
    Ok(false)
}

fn do_qr(app: &mut App) -> Result<(), (i32, Error)> {
    if let Some(ref content) = app.decrypted_content {
        let first_line = content.lines().next().unwrap_or("");
        match QRBuilder::new(first_line).build() {
            Ok(qr) => {
                app.decrypted_content = Some(qr.to_str());
                app.mode = AppMode::Display;
            }
            Err(e) => {
                app.message = Some(format!("QR error: {e}"));
            }
        }
    }
    Ok(())
}

fn do_edit(
    app: &mut App,
    config: &ParsConfig,
    _root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<(), (i32, Error)> {
    if let Some(ref entry_name) = app.selected_entry.clone() {
        // Leave TUI temporarily to run editor
        disable_raw_mode().ok();
        execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture).ok();

        let result = crate::command::edit::cmd_edit(config, None, entry_name);

        // Restore TUI — re-enter alternate screen and raw mode
        enable_raw_mode().ok();
        execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture).ok();

        // Force ratatui to fully redraw by resetting its internal diff buffer
        terminal.clear().map_err(|e| (1, anyhow!("Terminal clear error: {e}")))?;

        match result {
            Ok(_) => {
                app.message = Some("Edit complete".to_string());
            }
            Err((_, e)) => {
                app.message = Some(format!("Edit error: {e}"));
            }
        }
    }
    Ok(())
}

fn do_generate(
    app: &mut App,
    config: &ParsConfig,
    root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<(), (i32, Error)> {
    if let Some(ref entry_name) = app.selected_entry.clone() {
        // Ask user for confirmation before regenerating
        app.message = Some(format!("Regenerate '{}'? [y/N]", entry_name));

        // Draw the confirmation prompt
        terminal.draw(|frame| ui::draw(frame, app)).map_err(|e| (1, anyhow!("Draw error: {e}")))?;

        // Wait for confirmation
        loop {
            if event::poll(std::time::Duration::from_millis(5000))
                .map_err(|e| (1, anyhow!("Event poll error: {e}")))?
            {
                let evt = event::read().map_err(|e| (1, anyhow!("Event read error: {e}")))?;
                if let Event::Key(key) = evt {
                    match key.code {
                        KeyCode::Char('y') | KeyCode::Char('Y') => {
                            // Confirmed — regenerate
                            let cmd_config = crate::command::generate::GenerateCommandConfig {
                                base_dir: None,
                                no_symbols: false,
                                clip: false,
                                in_place: true,
                                force: true,
                                pass_name: entry_name,
                                pass_length: None,
                            };
                            match crate::command::generate::cmd_generate(config, cmd_config) {
                                Ok(_) => {
                                    app.message = Some("Password regenerated".to_string());
                                    re_decrypt(app, config, root);
                                }
                                Err((_, e)) => {
                                    app.message = Some(format!("Generate error: {e}"));
                                }
                            }
                            break;
                        }
                        _ => {
                            // Any other key = cancel
                            app.message = Some("Cancelled".to_string());
                            break;
                        }
                    }
                }
            } else {
                // Timeout = cancel
                app.message = Some("Cancelled (timeout)".to_string());
                break;
            }
        }
    }
    Ok(())
}

fn re_decrypt(app: &mut App, config: &ParsConfig, root: &Path) {
    if let Some(ref entry_name) = app.selected_entry {
        let tree_cfg = TreeConfig {
            root,
            target: entry_name,
            filter_type: FilterType::Disable,
            filters: Vec::new(),
        };
        let print_cfg = TreePrintConfig {
            dir_color: None,
            file_color: None,
            symbol_color: None,
            tree_color: None,
        };
        if let Ok(LsOrShow::Password(secret)) =
            ls_io(&config.executable_config.pgp_executable, &tree_cfg, &print_cfg)
        {
            app.decrypted_content = Some(secret.expose_secret().to_string());
        }
    }
}
