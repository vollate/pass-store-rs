use std::time::Instant;

use super::AppMode;

#[derive(PartialEq, Clone, Copy)]
pub enum PendingAction {
    Generate,
    Insert,
}

/// Screen rectangle (1-cell coordinates) computed by the renderer and consumed by
/// the mouse handler so clicks inside the action popup map to specific rows.
#[derive(Default, Clone, Copy, Debug)]
pub struct PopupRect {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
}

impl PopupRect {
    pub fn contains(&self, col: u16, row: u16) -> bool {
        col >= self.x && col < self.x + self.width && row >= self.y && row < self.y + self.height
    }
}

pub struct App {
    pub query: String,
    pub entries: Vec<String>,
    /// (entry_name, matched_char_indices) — indices are character offsets to highlight
    pub filtered: Vec<(String, Vec<u32>)>,
    pub cursor: usize,
    pub scroll_offset: usize,
    pub mode: AppMode,
    pub vim_enabled: bool,
    pub selected_entry: Option<String>,
    pub decrypted_content: Option<String>,
    pub message: Option<String>,
    pub action_cursor: usize,
    pub visible_height: usize,
    pub pending_d: bool,
    /// Buffer for typing a new entry name (Generate / Insert)
    pub name_input: String,
    /// What action to take once the name is confirmed
    pub pending_action: Option<PendingAction>,
    /// When set, the action popup shows a prominent y/N prompt instead of the action list
    pub confirm_prompt: Option<String>,
    /// Last-rendered action popup rect (for mouse hit-testing). 0-sized when not visible.
    pub action_popup_rect: PopupRect,
    /// Y of the first action item inside the popup (action_cursor=0 sits here).
    pub action_popup_first_action_y: u16,
    /// Last left-click row (for double-click detection on the result list).
    pub last_click_row: Option<u16>,
    /// Time of the last left-click (for double-click detection).
    pub last_click_time: Option<Instant>,
}

impl App {
    pub fn new(entries: Vec<String>, vim_enabled: bool) -> Self {
        let filtered: Vec<(String, Vec<u32>)> =
            entries.iter().map(|e| (e.clone(), Vec::new())).collect();
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
            name_input: String::new(),
            pending_action: None,
            confirm_prompt: None,
            action_popup_rect: PopupRect::default(),
            action_popup_first_action_y: 0,
            last_click_row: None,
            last_click_time: None,
        }
    }
}
