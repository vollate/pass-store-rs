//! Main event loop and per-mode keyboard/mouse handling.

use std::io;
use std::path::Path;

use anyhow::{anyhow, Error};
use crossterm::event::{
    self, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers, MouseEventKind,
};
use crossterm::execute;
use nucleo_matcher::{Config, Matcher};
use pars_core::config::cli::ParsConfig;
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

use super::actions::{
    do_copy, do_display, do_edit, do_generate_new, do_insert_new, do_qr, do_regenerate,
};
use super::app::{App, PendingAction};
use super::entries::filter_entries;
use super::{ui, AppMode};
use crate::util::unwrap_root_path;

pub fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    config: &ParsConfig,
    base_dir: Option<&str>,
) -> Result<(), (i32, Error)> {
    let mut matcher = Matcher::new(Config::DEFAULT);
    let root = unwrap_root_path(base_dir, config);

    loop {
        terminal.draw(|frame| ui::draw(frame, app)).map_err(|e| (1, anyhow!("Draw error: {e}")))?;

        if !event::poll(std::time::Duration::from_millis(200))
            .map_err(|e| (1, anyhow!("Event poll error: {e}")))?
        {
            continue;
        }

        let evt = event::read().map_err(|e| (1, anyhow!("Event read error: {e}")))?;

        // Windows (ConPTY) reports Press AND Release for every key; Linux/macOS only
        // report Press by default. Drop non-Press key events so the Enter that
        // launched `cargo run` doesn't get re-delivered as a Release-then-Press
        // and auto-select the first entry. Mouse / Resize events pass through.
        if let Event::Key(ref k) = evt {
            if k.kind != KeyEventKind::Press {
                continue;
            }
        }

        // Clear transient messages on most input (except in InputName / Action where they
        // may be confirmation messages we want to keep visible).
        if app.mode != AppMode::InputName && app.mode != AppMode::Action && app.message.is_some() {
            app.message = None;
        }

        match app.mode {
            AppMode::Insert => handle_insert_mode(app, evt, &mut matcher, terminal, config, &root)?,
            AppMode::Normal => handle_normal_mode(app, evt, &mut matcher, terminal, config, &root)?,
            AppMode::InputName => {
                handle_input_name_mode(app, evt, &mut matcher, terminal, config, &root)?
            }
            AppMode::Action => handle_action_mode(app, evt, terminal, config, &root)?,
            AppMode::Display => handle_display_mode(app, evt, terminal)?,
        }
    }
}

// ─── Mode handlers ──────────────────────────────────────────────────────────

fn handle_insert_mode(
    app: &mut App,
    evt: Event,
    matcher: &mut Matcher,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    _config: &ParsConfig,
    root: &Path,
) -> Result<(), (i32, Error)> {
    if let Event::Key(key) = evt {
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            match key.code {
                KeyCode::Char('c') => return Err((0, anyhow!("__exit__"))),
                KeyCode::Char('u') => {
                    app.query.clear();
                    refilter(app, matcher);
                }
                KeyCode::Char('w') => {
                    let trimmed = app.query.trim_end();
                    if let Some(pos) = trimmed.rfind(['/', ' ']) {
                        app.query.truncate(pos);
                    } else {
                        app.query.clear();
                    }
                    refilter(app, matcher);
                }
                KeyCode::Char('g') => {
                    open_name_input(app, PendingAction::Generate);
                }
                KeyCode::Char('n') => {
                    open_name_input(app, PendingAction::Insert);
                }
                _ => {}
            }
        } else {
            match key.code {
                KeyCode::Esc => {
                    if app.vim_enabled {
                        app.mode = AppMode::Normal;
                    } else {
                        return Err((0, anyhow!("__exit__")));
                    }
                }
                KeyCode::Char(c) => {
                    app.query.push(c);
                    refilter(app, matcher);
                }
                KeyCode::Backspace => {
                    app.query.pop();
                    refilter(app, matcher);
                }
                KeyCode::Up => move_cursor(app, -1),
                KeyCode::Down => move_cursor(app, 1),
                KeyCode::Enter => {
                    handle_select(app, root);
                    terminal.clear().ok();
                }
                _ => {}
            }
        }
    } else if let Event::Mouse(mouse) = evt {
        handle_mouse(app, mouse, root, terminal);
    }
    Ok(())
}

fn handle_normal_mode(
    app: &mut App,
    evt: Event,
    matcher: &mut Matcher,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    _config: &ParsConfig,
    root: &Path,
) -> Result<(), (i32, Error)> {
    if let Event::Key(key) = evt {
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            match key.code {
                KeyCode::Char('c') => return Err((0, anyhow!("__exit__"))),
                KeyCode::Char('d') => {
                    let half = app.visible_height / 2;
                    let max = app.filtered.len().saturating_sub(1);
                    app.cursor = (app.cursor + half).min(max);
                }
                KeyCode::Char('u') => {
                    let half = app.visible_height / 2;
                    app.cursor = app.cursor.saturating_sub(half);
                }
                KeyCode::Char('f') => {
                    let max = app.filtered.len().saturating_sub(1);
                    app.cursor = (app.cursor + app.visible_height).min(max);
                }
                KeyCode::Char('b') => {
                    app.cursor = app.cursor.saturating_sub(app.visible_height);
                }
                KeyCode::Char('g') => open_name_input(app, PendingAction::Generate),
                KeyCode::Char('n') => open_name_input(app, PendingAction::Insert),
                _ => {}
            }
            app.pending_d = false;
        } else {
            match key.code {
                KeyCode::Char('q') => return Err((0, anyhow!("__exit__"))),
                KeyCode::Char('i') => {
                    app.mode = AppMode::Insert;
                    app.pending_d = false;
                }
                KeyCode::Char('j') | KeyCode::Down => {
                    move_cursor(app, 1);
                    app.pending_d = false;
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    move_cursor(app, -1);
                    app.pending_d = false;
                }
                KeyCode::Char('d') => {
                    if app.pending_d {
                        app.query.clear();
                        refilter(app, matcher);
                        app.pending_d = false;
                    } else {
                        app.pending_d = true;
                    }
                }
                KeyCode::Char('D') => {
                    app.query.clear();
                    refilter(app, matcher);
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
                    handle_select(app, root);
                    terminal.clear().ok();
                }
                _ => app.pending_d = false,
            }
        }
    } else if let Event::Mouse(mouse) = evt {
        app.pending_d = false;
        handle_mouse(app, mouse, root, terminal);
    }
    Ok(())
}

fn handle_input_name_mode(
    app: &mut App,
    evt: Event,
    matcher: &mut Matcher,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    config: &ParsConfig,
    root: &Path,
) -> Result<(), (i32, Error)> {
    if let Event::Key(key) = evt {
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            match key.code {
                KeyCode::Char('c') => return Err((0, anyhow!("__exit__"))),
                KeyCode::Char('u') => app.name_input.clear(),
                _ => {}
            }
        } else {
            match key.code {
                KeyCode::Esc => {
                    app.name_input.clear();
                    app.pending_action = None;
                    app.mode = if app.vim_enabled { AppMode::Normal } else { AppMode::Insert };
                    terminal.clear().ok();
                }
                KeyCode::Char(c) => app.name_input.push(c),
                KeyCode::Backspace => {
                    app.name_input.pop();
                }
                KeyCode::Enter => {
                    if app.name_input.trim().is_empty() {
                        app.message = Some("Name cannot be empty".to_string());
                    } else {
                        let name = app.name_input.trim().to_string();
                        let action = app.pending_action;
                        app.name_input.clear();
                        app.pending_action = None;
                        app.mode = if app.vim_enabled { AppMode::Normal } else { AppMode::Insert };
                        terminal.clear().ok();
                        match action {
                            Some(PendingAction::Generate) => {
                                do_generate_new(app, config, root, terminal, matcher, &name)?;
                            }
                            Some(PendingAction::Insert) => {
                                do_insert_new(app, config, root, terminal, matcher, &name)?;
                            }
                            None => {}
                        }
                    }
                }
                _ => {}
            }
        }
    }
    Ok(())
}

fn handle_action_mode(
    app: &mut App,
    evt: Event,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    config: &ParsConfig,
    root: &Path,
) -> Result<(), (i32, Error)> {
    // Mouse interactions in the action popup
    if let Event::Mouse(mouse) = evt {
        match mouse.kind {
            MouseEventKind::Down(event::MouseButton::Left) => {
                if app.action_popup_rect.contains(mouse.column, mouse.row) {
                    // Action rows: 0..5 starting at action_popup_first_action_y
                    let first_y = app.action_popup_first_action_y;
                    if mouse.row >= first_y {
                        let idx = (mouse.row - first_y) as usize;
                        if idx < 5 {
                            app.action_cursor = idx;
                            // Double-click-like UX: a single click both selects AND activates.
                            return invoke_action(app, config, root, terminal, idx);
                        }
                    }
                } else {
                    // Click outside the popup → close it (treat like Esc/back)
                    app.selected_entry = None;
                    app.decrypted_content = None;
                    app.action_cursor = 0;
                    app.message = None;
                    app.mode = if app.vim_enabled { AppMode::Normal } else { AppMode::Insert };
                    terminal.clear().ok();
                }
            }
            MouseEventKind::ScrollUp => {
                if app.action_cursor > 0 {
                    app.action_cursor -= 1;
                }
            }
            MouseEventKind::ScrollDown
                if app.action_cursor < 4 => {
                    app.action_cursor += 1;
                }
            _ => {}
        }
        return Ok(());
    }

    let Event::Key(key) = evt else {
        return Ok(());
    };

    // Ctrl+C always exits — handle before plain-char shortcuts so it isn't
    // misread as the 'c' (copy) hotkey.
    if key.modifiers.contains(KeyModifiers::CONTROL) {
        if let KeyCode::Char('c') = key.code {
            return Err((0, anyhow!("__exit__")));
        }
        // Any other Ctrl-modified key in the action popup is ignored, so
        // combos like Ctrl+D / Ctrl+R don't accidentally trigger actions.
        return Ok(());
    }

    match key.code {
        KeyCode::Char('1') | KeyCode::Char('c') => {
            return invoke_action(app, config, root, terminal, 0);
        }
        KeyCode::Char('2') | KeyCode::Char('d') => {
            return invoke_action(app, config, root, terminal, 1);
        }
        KeyCode::Char('3') | KeyCode::Char('r') => {
            return invoke_action(app, config, root, terminal, 2);
        }
        KeyCode::Char('4') | KeyCode::Char('e') => {
            return invoke_action(app, config, root, terminal, 3);
        }
        KeyCode::Char('5') | KeyCode::Char('g') => {
            return invoke_action(app, config, root, terminal, 4);
        }
        KeyCode::Esc | KeyCode::Char('b') => {
            app.selected_entry = None;
            app.decrypted_content = None;
            app.action_cursor = 0;
            app.message = None;
            app.mode = if app.vim_enabled { AppMode::Normal } else { AppMode::Insert };
            terminal.clear().ok();
        }
        KeyCode::Char('q') => return Err((0, anyhow!("__exit__"))),
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
        KeyCode::Enter => {
            return invoke_action(app, config, root, terminal, app.action_cursor);
        }
        _ => {}
    }
    Ok(())
}

fn invoke_action(
    app: &mut App,
    config: &ParsConfig,
    root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    idx: usize,
) -> Result<(), (i32, Error)> {
    match idx {
        0 => {
            if do_copy(app, config, root)? {
                return Err((0, anyhow!("__exit__")));
            }
            terminal.clear().ok();
        }
        1 => {
            do_display(app, config, root)?;
            terminal.clear().ok();
        }
        2 => {
            do_qr(app, config, root)?;
            terminal.clear().ok();
        }
        3 => {
            do_edit(app, config, terminal)?;
            app.decrypted_content = None;
        }
        4 => do_regenerate(app, config, root, terminal)?,
        _ => {}
    }
    Ok(())
}

fn handle_display_mode(
    app: &mut App,
    evt: Event,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<(), (i32, Error)> {
    // Mouse events are intentionally ignored so the user can select+copy text
    // natively (mouse capture was disabled when entering Display mode).
    let Event::Key(key) = evt else {
        return Ok(());
    };

    // Only the keys advertised in the popup help line do anything; anything else
    // is ignored to match the displayed contract.
    if matches!(key.code, KeyCode::Char('q'))
        || (matches!(key.code, KeyCode::Char('c')) && key.modifiers.contains(KeyModifiers::CONTROL))
    {
        execute!(io::stdout(), EnableMouseCapture).ok();
        return Err((0, anyhow!("__exit__")));
    }

    if matches!(key.code, KeyCode::Esc | KeyCode::Enter) {
        execute!(io::stdout(), EnableMouseCapture).ok();
        app.decrypted_content = None;
        app.mode = AppMode::Action;
        terminal.clear().ok();
    }
    // Other keys: do nothing.
    Ok(())
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn refilter(app: &mut App, matcher: &mut Matcher) {
    app.filtered = filter_entries(&app.query, &app.entries, matcher);
    app.cursor = 0;
    app.scroll_offset = 0;
}

fn move_cursor(app: &mut App, delta: i32) {
    if delta < 0 {
        app.cursor = app.cursor.saturating_sub((-delta) as usize);
    } else if !app.filtered.is_empty() {
        let max = app.filtered.len() - 1;
        app.cursor = (app.cursor + delta as usize).min(max);
    }
}

fn open_name_input(app: &mut App, action: PendingAction) {
    app.pending_action = Some(action);
    app.name_input.clear();
    app.message = None;
    app.mode = AppMode::InputName;
}

fn handle_select(app: &mut App, _root: &Path) {
    if app.filtered.is_empty() {
        return;
    }
    let entry_name = app.filtered[app.cursor].0.clone();
    // Just open the action popup — DO NOT decrypt yet. Decryption happens lazily when
    // the user picks an action that actually needs the password content.
    app.selected_entry = Some(entry_name);
    app.decrypted_content = None;
    app.action_cursor = 0;
    app.mode = AppMode::Action;
}

fn handle_mouse(
    app: &mut App,
    mouse: event::MouseEvent,
    root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) {
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
            // Layout: input(3) + results_border(1) = 4 rows before list
            let results_start_y: u16 = 4;
            let click_y = mouse.row;
            if click_y >= results_start_y {
                let clicked_offset = (click_y - results_start_y) as usize;
                let target_index = app.scroll_offset + clicked_offset;
                if target_index < app.filtered.len() {
                    app.cursor = target_index;

                    // Double-click detection: same row clicked within 400ms acts as Enter.
                    let now = std::time::Instant::now();
                    let is_double = matches!(
                        (app.last_click_row, app.last_click_time),
                        (Some(r), Some(t))
                            if r == click_y
                                && now.duration_since(t)
                                    < std::time::Duration::from_millis(400)
                    );

                    if is_double {
                        app.last_click_row = None;
                        app.last_click_time = None;
                        handle_select(app, root);
                        terminal.clear().ok();
                    } else {
                        app.last_click_row = Some(click_y);
                        app.last_click_time = Some(now);
                    }
                }
            }
        }
        _ => {}
    }
}
