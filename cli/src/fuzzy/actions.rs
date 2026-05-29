//! All action handlers triggered from the action popup: copy, display, qr, edit, regenerate,
//! generate-new, insert-new, plus the lazy-decrypt helper and the y/N confirmation reader.

use std::io;
use std::path::Path;

use anyhow::{anyhow, Error, Result};
use crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind,
};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use fast_qr::QRBuilder;
use nucleo_matcher::Matcher;
use pars_core::clipboard::copy_to_clipboard;
use pars_core::config::cli::ParsConfig;
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::util::tree::{FilterType, TreeConfig, TreePrintConfig};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;
use secrecy::{ExposeSecret, SecretString};

use super::app::App;
use super::entries::{collect_entries, filter_entries};
use super::{ui, AppMode};

/// Lazily decrypt the currently-selected entry. Returns true on success.
/// Sets `app.message` on failure.
pub fn ensure_decrypted(app: &mut App, config: &ParsConfig, root: &Path) -> bool {
    if app.decrypted_content.is_some() {
        return true;
    }
    let Some(entry_name) = app.selected_entry.clone() else {
        return false;
    };
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
            true
        }
        Ok(LsOrShow::DirTree(_)) => {
            app.message = Some("Selected item is a directory".to_string());
            false
        }
        Err(e) => {
            app.message = Some(format!("Decryption failed: {e}"));
            false
        }
    }
}

/// Wait for y/Y/n/N/Esc input — returns true if confirmed.
/// Filters out non-Press key events (Release/Repeat) which some terminals send
/// and would otherwise be misinterpreted.
pub fn wait_yes_no(
    _terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<bool, (i32, Error)> {
    loop {
        if event::poll(std::time::Duration::from_millis(30000))
            .map_err(|e| (1, anyhow!("Event poll error: {e}")))?
        {
            if let Event::Key(key) =
                event::read().map_err(|e| (1, anyhow!("Event read error: {e}")))?
            {
                // Only react to Press events; ignore Release/Repeat which leak through
                // on some terminals and would otherwise be matched against our codes.
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                match key.code {
                    KeyCode::Char('y') | KeyCode::Char('Y') => return Ok(true),
                    KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => return Ok(false),
                    _ => {}
                }
            }
        } else {
            return Ok(false);
        }
    }
}

pub fn do_copy(app: &mut App, config: &ParsConfig, root: &Path) -> Result<bool, (i32, Error)> {
    if !ensure_decrypted(app, config, root) {
        return Ok(false);
    }
    if let Some(ref content) = app.decrypted_content {
        let first_line = content.lines().next().unwrap_or("").to_string();
        let secret: SecretString = first_line.into();
        match copy_to_clipboard(secret, &config.feature_config.clip_time) {
            Ok(_) => {
                app.message = Some("Copied to clipboard!".to_string());
                if config.feature_config.exit_on_copy {
                    return Ok(true);
                }
                app.selected_entry = None;
                app.decrypted_content = None;
                app.action_cursor = 0;
                app.mode = if app.vim_enabled { AppMode::Normal } else { AppMode::Insert };
            }
            Err(e) => {
                app.message = Some(format!("Clipboard error: {e}"));
            }
        }
    }
    Ok(false)
}

pub fn do_qr(app: &mut App, config: &ParsConfig, root: &Path) -> Result<(), (i32, Error)> {
    if !ensure_decrypted(app, config, root) {
        return Ok(());
    }
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

pub fn do_display(app: &mut App, config: &ParsConfig, root: &Path) -> Result<(), (i32, Error)> {
    if !ensure_decrypted(app, config, root) {
        return Ok(());
    }
    app.mode = AppMode::Display;
    Ok(())
}

pub fn do_edit(
    app: &mut App,
    config: &ParsConfig,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<(), (i32, Error)> {
    if let Some(ref entry_name) = app.selected_entry.clone() {
        leave_tui();
        let result = crate::command::edit::cmd_edit(config, None, entry_name);
        enter_tui();
        terminal.clear().map_err(|e| (1, anyhow!("Terminal clear error: {e}")))?;

        match result {
            Ok(_) => app.message = Some("Edit complete".to_string()),
            Err((_, e)) => app.message = Some(format!("Edit error: {e}")),
        }
    }
    Ok(())
}

pub fn do_regenerate(
    app: &mut App,
    config: &ParsConfig,
    _root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> Result<(), (i32, Error)> {
    if let Some(ref entry_name) = app.selected_entry.clone() {
        app.confirm_prompt = Some(format!("Regenerate password for '{}'?", entry_name));
        terminal.draw(|frame| ui::draw(frame, app)).ok();

        let confirmed = wait_yes_no(terminal)?;
        app.confirm_prompt = None;

        if !confirmed {
            app.message = Some("Cancelled".to_string());
            return Ok(());
        }

        // in_place=true replaces just the password line; do NOT pass force (they conflict).
        let cmd_config = crate::command::generate::GenerateCommandConfig {
            base_dir: None,
            no_symbols: false,
            clip: false,
            in_place: true,
            force: false,
            pass_name: entry_name,
            pass_length: None,
        };

        // Leave alternate screen so cmd_generate's stdout/stderr don't clobber our buffer
        leave_tui();
        let result = crate::command::generate::cmd_generate(config, cmd_config);
        enter_tui();
        terminal.clear().map_err(|e| (1, anyhow!("Terminal clear error: {e}")))?;

        match result {
            Ok(_) => {
                app.message = Some("Password regenerated".to_string());
                app.decrypted_content = None;
            }
            Err((_, e)) => {
                // Strip the noisy git failure tail — the regenerate itself usually succeeded
                let msg = e.to_string();
                let short = msg.split('\n').next().unwrap_or(&msg);
                app.message = Some(format!("Generate error: {short}"));
            }
        }
    }
    Ok(())
}

fn leave_tui() {
    disable_raw_mode().ok();
    execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture).ok();
}

fn enter_tui() {
    enable_raw_mode().ok();
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture).ok();
}

/// Generate a NEW password entry with the given name. Asks confirmation if it already exists.
pub fn do_generate_new(
    app: &mut App,
    config: &ParsConfig,
    root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    matcher: &mut Matcher,
    pass_name: &str,
) -> Result<(), (i32, Error)> {
    let target_path = root.join(format!("{}.gpg", pass_name));
    let exists = target_path.exists();

    if exists {
        app.confirm_prompt = Some(format!("'{}' exists. Overwrite?", pass_name));
        terminal.draw(|frame| ui::draw(frame, app)).ok();

        let confirmed = wait_yes_no(terminal)?;
        app.confirm_prompt = None;
        terminal.clear().ok();

        if !confirmed {
            app.message = Some("Cancelled".to_string());
            return Ok(());
        }
    }

    let cmd_config = crate::command::generate::GenerateCommandConfig {
        base_dir: None,
        no_symbols: false,
        clip: false,
        in_place: false,
        force: exists,
        pass_name,
        pass_length: None,
    };

    leave_tui();
    let result = crate::command::generate::cmd_generate(config, cmd_config);
    enter_tui();
    terminal.clear().ok();

    match result {
        Ok(_) => {
            app.message = Some(format!("Generated '{}'", pass_name));
            app.entries = collect_entries(root);
            app.filtered = filter_entries(&app.query, &app.entries, matcher);
            app.cursor = 0;
            app.scroll_offset = 0;
        }
        Err((_, e)) => {
            let msg = e.to_string();
            let short = msg.split('\n').next().unwrap_or(&msg);
            app.message = Some(format!("Generate error: {short}"));
        }
    }
    Ok(())
}

/// Insert a NEW password entry (prompts for password externally via stdin).
pub fn do_insert_new(
    app: &mut App,
    config: &ParsConfig,
    root: &Path,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    matcher: &mut Matcher,
    pass_name: &str,
) -> Result<(), (i32, Error)> {
    let target_path = root.join(format!("{}.gpg", pass_name));
    if target_path.exists() {
        app.message = Some(format!("'{}' already exists. Use edit instead.", pass_name));
        return Ok(());
    }

    // Leave TUI to read password from stdin
    leave_tui();
    let result = crate::command::insert::cmd_insert(config, None, pass_name, false, false, false);
    enter_tui();
    terminal.clear().map_err(|e| (1, anyhow!("Terminal clear error: {e}")))?;

    match result {
        Ok(_) => {
            app.message = Some(format!("Inserted '{}'", pass_name));
            app.entries = collect_entries(root);
            app.filtered = filter_entries(&app.query, &app.entries, matcher);
            app.cursor = 0;
            app.scroll_offset = 0;
        }
        Err((_, e)) => {
            app.message = Some(format!("Insert error: {e}"));
        }
    }
    Ok(())
}
