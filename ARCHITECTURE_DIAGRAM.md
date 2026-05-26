# Pass-Store-RS Architecture Diagram

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CLI Entry Point                           │
│                    (pars/src/main.rs)                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         Argument Parser (clap)                              │
│         cli/src/parser/mod.rs                               │
│         Supports: ls, show, find, search (new), etc.       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────┬───────────────────┐
        │ SubCommand        │ SubCommand        │
        │ Dispatcher        │ Dispatcher        │
        │                   │                   │
        │ ls/show/search    │ find              │
        └───┬───────────────┴───────────────────┘
            │
            ├─────────────┬──────────────────┬──────────────────┐
            ▼             ▼                  ▼                  ▼
    ┌────────────┐ ┌────────────┐ ┌──────────────┐ ┌────────────────┐
    │ cmd_ls()   │ │ cmd_find() │ │ cmd_search() │ │ fuzzy_display()│
    │ (existing) │ │ (existing) │ │ (new)        │ │ (TUI)          │
    └─────┬──────┘ └─────┬──────┘ └──────┬───────┘ └────────────────┘
          │               │               │
          │               │               └─────────────┐
          │               │                             │
          └──────┬────────┴─────────────────────────────┘
                 ▼
    ┌──────────────────────────────────────┐
    │  Core Library Operations             │
    │  (pars_core::operation::*)           │
    │                                      │
    │  • ls_io() - main entry point        │
    │  • ls_dir() - list only              │
    │  • find_term() - filtered listing    │
    └──────────────────────────────────────┘
                 │
                 ▼
    ┌──────────────────────────────────────┐
    │  Tree System                         │
    │  (pars_core::util::tree::*)          │
    │                                      │
    │  • DirTree - hierarchical structure  │
    │  • TreeNode - individual entries     │
    │  • TreeConfig - configuration        │
    │  • Filtering & traversal             │
    └──────────────────────────────────────┘
                 │
                 ├────────────┬────────────┐
                 ▼            ▼            ▼
            ┌─────────┐ ┌──────────┐ ┌──────────┐
            │Filesystem│GPG Decrypt│ Formatting
            │Traversal │ (PGPClient)
            └─────────┘ └──────────┘ └──────────┘
```

## 2. Password Tree Structure in Memory

```
DirTree (Arena-allocated with Bumpalo)
│
├── map: BumpVec<TreeNode>    ← Index-based node storage
│   ├── [0] TreeNode           ← Root node (password store root)
│   │   ├── name: ""
│   │   ├── parent: None
│   │   ├── children: [1, 2, 3]  ← Indices into map
│   │   └── node_type: Dir
│   │
│   ├── [1] TreeNode           ← Directory
│   │   ├── name: "work"
│   │   ├── parent: Some(0)
│   │   ├── children: [4, 5]
│   │   └── node_type: Dir
│   │
│   ├── [2] TreeNode           ← File
│   │   ├── name: "personal"
│   │   ├── parent: Some(0)
│   │   ├── children: []
│   │   └── node_type: File
│   │
│   ├── [3] TreeNode           ← Symlink
│   │   ├── name: "archive"
│   │   ├── symlink_target: Some("/path/to/target")
│   │   └── node_type: Symlink
│   │
│   ├── [4] TreeNode
│   │   ├── name: "github"
│   │   ├── parent: Some(1)
│   │   └── node_type: File
│   │
│   └── [5] TreeNode
│       ├── name: "gitlab"
│       ├── parent: Some(1)
│       └── node_type: File
│
└── root: 0  ← Index of root node
```

## 3. Data Flow: From CLI to Display

### Current Flow (ls command):
```
User Input: pars
    │
    ▼
Parsed Args
    │
    ├── base_dir: None
    └── target: None
    │
    ▼
cmd_ls(config, base_dir=None, target="")
    │
    ├── Determine root path
    ├── Create TreeConfig {
    │       root: /home/user/.password-store,
    │       target: "",
    │       filter_type: Disable,
    │       filters: []
    │   }
    │
    └─ ▼─────────────────────────────────┐
         ls_io(pgp_executable, tree_cfg)  │
            │                             │
            ├─ target is dir? → YES      │
            │                             │
            ├─ Build DirTree              │
            │   DirTree::new(cfg, bump)   │
            │     • read_dir recursively  │
            │     • build indices         │
            │     • apply filters         │
            │     • detect symlinks       │
            │                             │
            ├─ Format tree string         │
            │   tree.print_tree(cfg)      │
            │     • traverse via stack    │
            │     • add box chars         │
            │     • strip .gpg suffix     │
            │                             │
            └─ ▼──────────────────────────┘
                 Return: LsOrShow::DirTree(String)
                    │
                    ▼
                println!("{tree}")
```

### New Flow (proposed fuzzy search):
```
User Input: pars search [query]
    │
    ▼
Parsed Args
    │
    ├── base_dir: None
    └── query: Option<&str>
    │
    ▼
cmd_search(config, base_dir, query)
    │
    ├── Determine root path
    ├── Create TreeConfig {
    │       root: /home/user/.password-store,
    │       target: "",
    │       filter_type: Disable,
    │       filters: []
    │   }
    │
    └─ ▼────────────────────────────┐
         fuzzy_display(root, query)  │
            │                        │
            ├─ TUI Fuzzy Finder      │
            │   ratatui                │
            │   nucleo-matcher       │
            │                        │
            ├─ Build DirTree for    │
            │   all passwords         │
            │   • DirTree::new()     │
            │   • Flatten to list    │
            │   • nucleo filter      │
            │                        │
            ├─ Interactive Loop      │
            │   • Display matches    │
            │   • Key handling       │
            │   • Preview on hover   │
            │                        │
            └─ ▼──────────────────────┘
                 Return: String (selected path)
                    │
                    ▼
                ls_io(pgp, tree_cfg with selected path)
                    │
                    ├─ target is file? → YES
                    ├─ Append .gpg extension
                    ├─ Decrypt via PGPClient
                    │
                    └─ ▼
                        Return: LsOrShow::Password(SecretString)
                            │
                            ▼
                        println!("{password}")
```

## 4. Tree Node Access Patterns

### Pattern 1: Iterate all nodes (DFS)
```rust
// Example: collect all file paths
fn get_all_password_paths(tree: &DirTree) -> Vec<String> {
    let mut paths = Vec::new();
    let mut stack = vec![tree.root];
    
    while let Some(idx) = stack.pop() {
        let node = &tree.map[idx];
        
        if node.node_type == NodeType::File && node.visible {
            paths.push(node.name.clone());
        }
        
        // Add children to stack (in reverse for correct order)
        for &child_idx in node.children.iter().rev() {
            stack.push(child_idx);
        }
    }
    paths
}
```

### Pattern 2: Filter with regex (using existing system)
```rust
// Example: find passwords matching pattern
let mut config = TreeConfig {
    root: &root,
    target: "",
    filter_type: FilterType::Include,
    filters: vec![Regex::new("github")?],
};

let tree = DirTree::new(&config, &bump)?;
let formatted = tree.print_tree(&print_cfg)?;
```

### Pattern 3: Full path reconstruction
```rust
// Walk up parent chain to build full path
fn get_full_path(tree: &DirTree, mut node_idx: usize) -> String {
    let mut parts = Vec::new();
    
    loop {
        let node = &tree.map[node_idx];
        parts.push(node.name.clone());
        
        match node.parent {
            Some(parent_idx) => node_idx = parent_idx,
            None => break,
        }
    }
    
    parts.reverse();
    parts.join("/")
}
```

## 5. Fuzzy Finder Pseudo-Code Architecture

```rust
pub struct FuzzyState {
    tree: DirTree,           // All passwords
    all_paths: Vec<String>,  // Flattened paths
    query: String,           // Current search input
    matches: Vec<Match>,     // Filtered + scored results
    selected_idx: usize,     // Highlighted entry
}

pub struct Match {
    path: String,
    score: u32,              // From nucleo
    indices: Vec<usize>,     // For highlighting
}

fn fuzzy_display(root: &Path, initial_query: Option<&str>) -> Result<String> {
    // 1. Build password tree
    let tree = DirTree::new(&tree_cfg, &bump)?;
    let all_paths = flatten_tree(&tree);
    
    // 2. Initialize TUI
    let mut terminal = ratatui::Terminal::new()?;
    let mut state = FuzzyState {
        tree,
        all_paths,
        query: initial_query.unwrap_or("").to_string(),
        matches: Vec::new(),
        selected_idx: 0,
    };
    
    // 3. Initial filter
    update_matches(&mut state);
    
    // 4. Event loop
    loop {
        // Render
        terminal.draw(|f| draw_ui(f, &state))?;
        
        // Handle input
        match read_event()? {
            Key::Char(c) => {
                state.query.push(c);
                update_matches(&mut state);
            },
            Key::Backspace => {
                state.query.pop();
                update_matches(&mut state);
            },
            Key::Up => state.selected_idx = state.selected_idx.saturating_sub(1),
            Key::Down => state.selected_idx = (state.selected_idx + 1).min(state.matches.len() - 1),
            Key::Enter => return Ok(state.matches[state.selected_idx].path.clone()),
            Key::Esc => return Err("Cancelled".into()),
        }
    }
}

fn update_matches(state: &mut FuzzyState) {
    state.matches.clear();
    
    for path in &state.all_paths {
        if let Some((score, indices)) = nucleo_matcher.fuzzy_match(path, &state.query) {
            state.matches.push(Match {
                path: path.clone(),
                score,
                indices,
            });
        }
    }
    
    // Sort by score (descending)
    state.matches.sort_by(|a, b| b.score.cmp(&a.score));
}

fn draw_ui(f: &mut Frame, state: &FuzzyState) {
    // Input field at top
    // List of matches in middle
    // Preview pane (optional) on right
    // Status bar at bottom
}
```

## 6. Key Integration Points

### Files to Modify:
1. `cli/src/fuzzy/mod.rs` - Implement fuzzy_display()
2. `cli/src/command/mod.rs` - Add search module (optional)
3. `cli/src/parser/sub_command.rs` - Add Search command (optional)
4. `cli/src/parser/mod.rs` - Handle Search command (optional)

### Files to Reference (Read-Only):
1. `core/src/util/tree/` - Tree system
2. `core/src/operation/ls_or_show.rs` - Existing ls logic
3. `cli/src/command/ls.rs` - How ls calls core
4. `core/src/operation/find.rs` - How find uses filtering

### Dependencies Already Available:
- `ratatui = "0.29.0"` - TUI rendering
- `nucleo-matcher = "0.3.1"` - Fuzzy matching
- `colored = ?` - Coloring
- `anyhow = "1.0.97"` - Error handling
- `crossterm = ?` (possibly via ratatui) - Terminal control

