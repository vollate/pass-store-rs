# Pass-Store-RS: TUI Fuzzy Search Infrastructure Analysis

## Project Overview
This is a Rust password manager (`pass-store-rs`) that's a compatible reimplementation of the original shell-based `pass`. It has a CLI built with `clap` and a core library for password operations.

**Key Directories:**
- `cli/src/` - CLI application code
- `core/src/` - Core library for password operations
- `cli/src/fuzzy/` - Stub for fuzzy search functionality (NOT YET IMPLEMENTED)
- `core/src/util/tree/` - Tree data structure for directory listing

---

## 1. Fuzzy Module Status

**File:** `cli/src/fuzzy/mod.rs`

```rust
use std::path::Path;

pub(crate) fn fuzzy_display(_root: &Path, _target_str: &str) {}
```

**Status:** ⚠️ **COMPLETELY EMPTY STUB**
- Only has a placeholder function `fuzzy_display()` with no implementation
- Takes root path and target string, but does nothing
- **Currently unused** - never called from anywhere in the codebase

---

## 2. Dependencies Available

**Cargo.toml Dependencies:**
- ✅ `ratatui = "0.29.0"` - TUI framework (imported but NOT USED anywhere)
- ✅ `nucleo-matcher = "0.3.1"` - Fuzzy matching library (imported but NOT USED anywhere)
- ✅ `secrecy = "0.10.3"` - Secret string handling
- ✅ `clap = "4.5.28"` - CLI argument parsing
- ✅ `colored = ?` - Coloring (used in tree printing)
- ✅ `log = "0.4.26"` - Logging
- ✅ `anyhow = "1.0.97"` - Error handling

**Key finding:** Both `ratatui` and `nucleo-matcher` are dependencies but completely unused. This is ideal for implementing a TUI fuzzy finder!

---

## 3. Current LS/Show Command Architecture

**File:** `cli/src/command/ls.rs`

The `ls` command currently:
1. Takes optional `target` path parameter
2. Calls `ls_io()` from core to handle listing or showing
3. Returns either:
   - `LsOrShow::DirTree(String)` - tree structure as a formatted string
   - `LsOrShow::Password(SecretString)` - actual password content

```rust
pub fn cmd_ls(
    config: &ParsConfig,
    base_dir: Option<&str>,
    clip: Option<usize>,
    qrcode: Option<usize>,
    target: Option<&str>,
) -> Result<(), (i32, Error)>
```

**Usage Pattern:**
- `pars` or `pars ls` - lists all passwords
- `pars ls path/to/folder` - lists passwords in a folder
- `pars show path/to/password` - shows a password (internally same as `cmd_ls`)

---

## 4. Tree Data Structure & Enumeration

**Location:** `core/src/util/tree/`

### DirTree Structure (`tree/mod.rs`):
```rust
pub struct DirTree<'a> {
    pub map: BumpVec<'a, TreeNode>,
    pub root: usize,
}

pub struct TreeNode {
    pub name: String,
    pub parent: Option<usize>,
    pub children: Vec<usize>,
    pub node_type: NodeType,  // File, Dir, Symlink, etc.
    pub symlink_target: Option<String>,
    pub is_recursive: bool,
    pub visible: bool,
}

pub enum NodeType {
    File,
    Dir,
    Symlink,
    Other,
    Invalid,
}
```

### Key Functions in `tree/convert.rs`:

1. **`DirTree::new(config, bump)`** - Main constructor
   - Builds entire directory tree from root
   - Applies filters (include/exclude)
   - Handles symlinks and recursion detection
   - Returns allocated tree ready for traversal

2. **`build_tree()`** - Internal tree builder
   - Recursive depth-first traversal using stack
   - Detects recursive symlinks
   - Excludes `.git` and `.gpg-id` files
   - Maintains parent-child relationships via indices

3. **`apply_whitelist()`** - Filtering logic
   - Include-list mode: only show matching entries and their parents
   - Exclude-list mode: hide matching entries
   - Preserves tree structure for matched entries

4. **`shrink_tree()`** - Removes hidden nodes
   - Cleans up children vectors
   - Maintains tree consistency

### Tree Traversal (`tree/print.rs`):

The `print_tree()` function shows how to traverse the tree:
```rust
pub fn print_tree(&self, config: &TreePrintConfig) -> Result<String>
```
- Uses stack-based traversal
- Tracks nesting level for tree formatting
- Returns formatted string with box-drawing characters

---

## 5. Existing Listing Functions

### `ls_or_show.rs` Core Functions:

#### `ls_io()` - Main entry point
```rust
pub fn ls_io(
    pgp_executable: &str,
    tree_cfg: &TreeConfig,
    print_cfg: &TreePrintConfig,
) -> Result<LsOrShow>
```
- **Purpose:** List or show based on path
- **Returns:** Either a DirTree (for directories) or Password (for files)
- **Symlink handling:** Resolves symlinks before checking
- **Error handling:** Validates paths, reports clear errors

#### `ls_dir()` - List-only function
```rust
pub fn ls_dir(tree_cfg: &TreeConfig, print_cfg: &TreePrintConfig) -> Result<String>
```
- **Purpose:** List directory only (no password decryption)
- **Returns:** Formatted tree string
- **Use case:** Perfect for fuzzy finder preview

### TreeConfig Structure:
```rust
pub struct TreeConfig<'a> {
    pub root: &'a Path,           // Password store root
    pub target: &'a str,          // Subdirectory/entry to target
    pub filter_type: FilterType,  // Include/Exclude/Disable
    pub filters: Vec<Regex>,      // Regex patterns for filtering
}
```

### TreePrintConfig Structure:
```rust
pub struct TreePrintConfig {
    pub dir_color: Option<Color>,
    pub file_color: Option<Color>,
    pub symbol_color: Option<Color>,
    pub tree_color: Option<Color>,
}
```

---

## 6. Find/Search Infrastructure

**Location:** `core/src/operation/find.rs`

```rust
pub fn find_term(
    terms: &Vec<&str>,
    tree_cfg: &TreeConfig,
    print_cfg: &TreePrintConfig,
) -> Result<String>
```

**How it works:**
1. Takes search terms (regex patterns)
2. Creates TreeConfig with `FilterType::Include`
3. Converts search terms to regex filters
4. Uses the tree system to show only matching entries
5. Returns formatted tree string

**Perfect building block:** This shows how to use the tree system for filtered listing!

---

## 7. How Passwords Are Enumerated

### Entry Point: `ls_or_show.rs` → `ls_io()`

1. **Start with root path** → Apply target
2. **Check if target is directory:**
   - YES: Build DirTree and return formatted string
   - NO: Assume it's a password file
3. **For files:**
   - Append `.gpg` extension
   - Check if file exists
   - Decrypt using GPG via `PGPClient`
   - Return SecretString

### Tree Building Process:
- Uses `fs::read_dir()` with sorted entries
- Recursively descends directories
- Maintains hierarchy via parent/child indices
- Filters out `.git` and `.gpg-id` automatically
- Detects and prevents infinite symlink loops

### Flat List Generation:
To get a **flat list of all passwords** for fuzzy matching:
```
1. Build DirTree from root (target = "")
2. Flatten tree via DFS traversal:
   - Collect all visible File nodes
   - Skip directories
   - Remove .gpg suffix
   - Generate full paths relative to root
```

---

## 8. CLI Command Flow

**File:** `cli/src/parser/mod.rs` and `sub_command.rs`

When `pars` runs with no arguments or just `pars ls`:
```
main.rs
  → CliParser::parse_from(args)
  → handle_cli() with SubCommands::Ls
  → command::ls::cmd_ls()
    → TreeConfig { root, target="", filter_type: Disable, filters: [] }
    → ls_io() → lists entire password store
```

**Key SubCommands:**
- `Ls { clip, qrcode, sub_folder }` - List (with optional copy/QR)
- `Show { clip, qrcode, pass_name }` - Show password (same implementation as ls)
- `Find { names }` - Find with regex filtering

---

## 9. Current Output Format

When listing, the tree is printed as a string with box-drawing characters:
```
├── dir1
│   ├── file1
│   └── file2
├── dir2
│   └── file3
└── dir3
```

And `.gpg` extensions are stripped before display.

---

## 10. Building Blocks Summary for TUI Fuzzy Finder

### What's Ready to Use:

1. **Tree Enumeration:** `DirTree::new()` - build complete password tree
2. **Filtering:** Already has regex Include/Exclude in TreeConfig
3. **Traversal:** `DirTree` provides flat access via `map` vector
4. **Single-selection:** Can call `ls_io()` to show selected password
5. **Colorization:** `TreePrintConfig` + `colored` crate for rendering
6. **Password Display:** `PGPClient` for decryption (already in core)

### What Needs Implementation:

1. **Fuzzy matching UI:** Ratatui TUI with input field
2. **Nucleo-based matching:** Fuzzy score/filter entries
3. **Interactive selection:** Up/down/enter keys
4. **Preview pane:** Show password content or tree preview
5. **Exit/cancel handling:** Graceful TUI exit

---

## 11. API Design Suggestions

### Option A: Minimal Fuzzy Display Function
```rust
pub fn fuzzy_display(root: &Path, initial_query: Option<&str>) -> Result<String> {
    // Start interactive TUI fuzzy finder
    // Return selected password path
    // Or error if cancelled
}
```

### Option B: With Configuration
```rust
pub struct FuzzyConfig {
    pub preview_pane: bool,
    pub multiselect: bool,
    pub height_ratio: f32,
}

pub fn fuzzy_display_with_config(
    root: &Path, 
    config: FuzzyConfig
) -> Result<String>
```

### Option C: Integrate with TreeConfig
```rust
pub fn fuzzy_display(
    root: &Path,
    tree_cfg: &TreeConfig,  // Reuse existing config
    pgp_executable: &str,
) -> Result<String>  // Returns selected path
```

---

## 12. Integration Points

### Where to Call Fuzzy Finder:

1. **Default action when no args:**
   - Currently: `pars` lists everything
   - Could be: `pars` opens fuzzy finder

2. **New command:**
   - `pars fzf` or `pars search` or `pars select`

3. **As fallback:**
   - When more than N entries shown, offer fuzzy

### Integration with existing code:

```rust
// In parser/sub_command.rs - add new command
Find { names }  // existing
Search { query }  // new fuzzy command

// In parser/mod.rs - handle new command
Some(SubCommands::Search { query }) => {
    command::search::cmd_search(&config, cli_args.base_dir, query)?;
}

// In command/search.rs - call fuzzy_display
pub fn cmd_search(config: &ParsConfig, base_dir: Option<&str>, query: Option<&str>) -> Result<()> {
    let root = unwrap_root_path(base_dir, config);
    let selected = fuzzy::fuzzy_display(&root, query)?;
    // Then call ls_io with selected path
}
```

---

## Summary

### Current State:
- ✅ All tree enumeration working
- ✅ Filtering system ready
- ✅ CLI framework in place
- ✅ Dependencies installed (ratatui, nucleo-matcher)
- ❌ Fuzzy TUI not implemented

### Ready to Build:
A TUI fuzzy finder that:
1. Uses existing `DirTree::new()` to enumerate passwords
2. Applies `nucleo-matcher` for fuzzy filtering
3. Uses `ratatui` to display interactive selection
4. Returns selected path to existing `ls_io()` for decryption/display

The infrastructure is 90% there. Just need to build the UI layer!
