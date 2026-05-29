use super::AppMode;

#[derive(PartialEq, Clone, Copy)]
pub enum PendingAction {
    Generate,
    Insert,
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
        }
    }
}
