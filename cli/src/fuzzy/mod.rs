//! Interactive fuzzy search TUI for the password store.
//!
//! Module layout:
//!   - `app`     — `App` state struct, `AppMode`, `PendingAction` enums
//!   - `entries` — password store walking and fuzzy filtering
//!   - `events`  — main event loop and keyboard/mouse handlers
//!   - `actions` — copy/display/qr/edit/regenerate/generate-new/insert-new handlers
//!   - `ui`      — ratatui rendering

mod actions;
mod app;
mod entries;
mod events;
pub mod ui;

use std::io;

use anyhow::{anyhow, Error, Result};
pub use app::App;
use crossterm::event::{DisableMouseCapture, EnableMouseCapture};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
pub use entries::collect_entries;
use pars_core::config::cli::ParsConfig;
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

use crate::util::unwrap_root_path;

#[derive(PartialEq, Clone, Copy)]
pub enum AppMode {
    /// Insert mode: typing filters entries
    Insert,
    /// Normal mode (vim): navigate with j/k
    Normal,
    /// Action popup: choose what to do with the selected password
    Action,
    /// Display: show decrypted content or QR as centered popup
    Display,
    /// Input a name for a new entry (Generate / Insert new)
    InputName,
}

/// Entry point called from the CLI parser when `pars` is invoked with no subcommand.
pub fn interactive_search(config: &ParsConfig, base_dir: Option<&str>) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let entries = collect_entries(&root);

    if entries.is_empty() {
        eprintln!("Password store is empty. Use 'pars insert' to add entries.");
        return Ok(());
    }

    enable_raw_mode().map_err(|e| (1, anyhow!("Failed to enable raw mode: {e}")))?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)
        .map_err(|e| (1, anyhow!("Failed to enter alternate screen: {e}")))?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal =
        Terminal::new(backend).map_err(|e| (1, anyhow!("Failed to create terminal: {e}")))?;

    let vim_enabled = config.feature_config.vim_mode;
    let mut app = App::new(entries, vim_enabled);
    let result = events::run_app(&mut terminal, &mut app, config, base_dir);

    // Clean shutdown: clear the alt screen so any leftover (display popup, errors) is
    // wiped, then restore the previous screen and re-enable normal cursor/input.
    let _ = terminal.clear();
    disable_raw_mode().ok();
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture,
        crossterm::cursor::Show
    )
    .ok();
    terminal.show_cursor().ok();

    // The event loop signals normal exit by returning Err with the sentinel "__exit__"
    // (this lets handlers escape from deeply-nested contexts via `?`). Convert to Ok.
    match result {
        Ok(()) => Ok(()),
        Err((code, e)) if e.to_string() == "__exit__" => {
            if code == 0 {
                Ok(())
            } else {
                Err((code, e))
            }
        }
        Err(other) => Err(other),
    }
}
