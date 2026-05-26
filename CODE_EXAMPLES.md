# Pass-Store-RS: Concrete Code Examples

## 1. How to Enumerate All Passwords

### Using DirTree
```rust
use pars_core::util::tree::{DirTree, TreeConfig, FilterType};
use bumpalo::Bump;
use std::path::Path;

fn list_all_passwords(root: &Path) -> anyhow::Result<Vec<String>> {
    let tree_cfg = TreeConfig {
        root,
        target: "",  // Empty target = root of password store
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    
    let bump = Bump::new();
    let tree = DirTree::new(&tree_cfg, &bump)?;
    
    let mut passwords = Vec::new();
    let mut stack = vec![tree.root];
    
    // DFS traversal
    while let Some(node_idx) = stack.pop() {
        let node = &tree.map[node_idx];
        
        // Collect only visible files (skip directories)
        if node.node_type == pars_core::util::tree::NodeType::File && node.visible {
            passwords.push(node.name.clone());
        }
        
        // Push children to stack in reverse order for correct traversal
        for &child_idx in node.children.iter().rev() {
            stack.push(child_idx);
        }
    }
    
    Ok(passwords)
}
```

### What tree.map looks like
```
tree.map is a BumpVec<TreeNode> where each node has:
- name: "github" or "work/gitlab" etc
- parent: Some(idx) pointing to parent node or None for root
- children: Vec of indices to children
- node_type: File, Dir, Symlink, etc
- visible: bool (used for filtering)

Access pattern:
tree.map[0]           // Root node
tree.map[1]           // First child
tree.map[node.parent] // Parent node (if exists)
tree.map[node.children[0]] // First child
```

## 2. How to Filter Passwords

### Using Include/Exclude Filters
```rust
use regex::Regex;
use pars_core::util::tree::{DirTree, TreeConfig, FilterType};

fn find_passwords_matching(root: &Path, pattern: &str) -> anyhow::Result<Vec<String>> {
    let tree_cfg = TreeConfig {
        root,
        target: "",
        filter_type: FilterType::Include,  // Only show matches
        filters: vec![Regex::new(pattern)?],  // Can have multiple patterns
    };
    
    let bump = Bump::new();
    let tree = DirTree::new(&tree_cfg, &bump)?;  // Filtering happens here
    
    // Now tree only contains nodes matching the filter + their parents
    let mut results = Vec::new();
    let mut stack = vec![tree.root];
    
    while let Some(node_idx) = stack.pop() {
        let node = &tree.map[node_idx];
        
        if node.node_type == NodeType::File && node.visible {
            results.push(node.name.clone());
        }
        
        for &child_idx in node.children.iter().rev() {
            stack.push(child_idx);
        }
    }
    
    Ok(results)
}

// Example usage:
find_passwords_matching(&root, "github")?  // All paths containing "github"
find_passwords_matching(&root, "^work/")?  // Regex: all in work/ directory
```

## 3. How to Display a Password

### Using ls_io from core
```rust
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::util::tree::{TreeConfig, TreePrintConfig, FilterType};

fn display_password(
    root: &Path,
    password_path: &str,  // e.g., "work/github"
    pgp_executable: &str,
) -> anyhow::Result<()> {
    let tree_cfg = TreeConfig {
        root,
        target: password_path,
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    
    let print_cfg = TreePrintConfig {
        dir_color: None,
        file_color: None,
        symbol_color: None,
        tree_color: None,
    };
    
    let res = ls_io(pgp_executable, &tree_cfg, &print_cfg)?;
    
    match res {
        LsOrShow::Password(mut passwd) => {
            // Password is a SecretString - must be zeroized after use
            use secrecy::ExposeSecret;
            println!("{}", passwd.expose_secret());
            passwd.zeroize();  // Important: clear from memory
        },
        LsOrShow::DirTree(tree) => {
            // If it was a directory, print the tree instead
            println!("{tree}");
        }
    }
    
    Ok(())
}
```

## 4. How to Build a Full Path from Tree Node Index

### Reconstruct path from node indices
```rust
use pars_core::util::tree::DirTree;

fn get_full_path(tree: &DirTree, mut node_idx: usize) -> String {
    let mut parts = Vec::new();
    
    loop {
        let node = &tree.map[node_idx];
        parts.push(node.name.clone());
        
        match node.parent {
            Some(parent_idx) => node_idx = parent_idx,
            None => break,  // Reached root
        }
    }
    
    parts.reverse();
    
    // parts[0] should be empty string (root), so skip it
    if !parts.is_empty() && parts[0].is_empty() {
        parts.remove(0);
    }
    
    parts.join("/")
}

// Example:
let path = get_full_path(&tree, 5);  // Returns "work/github"
```

## 5. How Nucleo-Matcher Works

### Basic fuzzy matching
```rust
use nucleo_matcher::EngineBuilder;

fn fuzzy_match_passwords(
    passwords: &[String],
    query: &str,
) -> Vec<(String, u32)> {
    let mut engine = EngineBuilder::new().build();
    let mut results = Vec::new();
    
    for password in passwords {
        // Try to fuzzy match
        if let Some(score) = engine.fuzzy_match(password, query) {
            results.push((password.clone(), score));
        }
    }
    
    // Sort by score (highest first)
    results.sort_by(|a, b| b.1.cmp(&a.1));
    
    results
}

// Example usage:
let passwords = vec!["work/github".to_string(), "personal/github".to_string()];
let matches = fuzzy_match_passwords(&passwords, "gh");
// Returns: [("work/github", 500), ("personal/github", 490)]
```

## 6. How to Use Ratatui for Display

### Basic TUI setup
```rust
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, List, ListItem};
use crossterm::event::{self, Event, KeyCode};
use crossterm::terminal::{EnterAlternateScreen, ExitAlternateScreen};
use std::io;

fn basic_tui_example(items: Vec<String>) -> io::Result<String> {
    // Setup terminal
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = io::stdout();
    stdout.execute(EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    
    let mut selected = 0;
    
    loop {
        // Draw
        terminal.draw(|f| {
            let items_list: Vec<ListItem> = items
                .iter()
                .enumerate()
                .map(|(i, item)| {
                    let style = if i == selected {
                        Style::default().bg(Color::Blue)
                    } else {
                        Style::default()
                    };
                    ListItem::new(item.clone()).style(style)
                })
                .collect();
            
            let list = List::new(items_list)
                .block(Block::default().borders(Borders::ALL).title("Passwords"));
            
            f.render_widget(list, f.size());
        })?;
        
        // Handle input
        if let Event::Key(key) = event::read()? {
            match key.code {
                KeyCode::Up => selected = selected.saturating_sub(1),
                KeyCode::Down => selected = (selected + 1).min(items.len() - 1),
                KeyCode::Enter => return Ok(items[selected].clone()),
                KeyCode::Esc => return Err(io::Error::new(io::ErrorKind::Other, "Cancelled")),
                _ => {}
            }
        }
    }
    
    // Cleanup terminal
    crossterm::terminal::disable_raw_mode()?;
    io::stdout().execute(ExitAlternateScreen)?;
}
```

## 7. Complete Example: Simple Fuzzy Finder

### Put it all together
```rust
use anyhow::Result;
use bumpalo::Bump;
use nucleo_matcher::EngineBuilder;
use pars_core::util::tree::{DirTree, TreeConfig, TreeNode, NodeType, FilterType};
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use ratatui::prelude::*;
use std::path::Path;
use crossterm::event::{self, Event, KeyCode};

pub fn simple_fuzzy_finder(root: &Path, pgp_executable: &str) -> Result<()> {
    // Step 1: Build tree and get all passwords
    let tree_cfg = TreeConfig {
        root,
        target: "",
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    
    let bump = Bump::new();
    let tree = DirTree::new(&tree_cfg, &bump)?;
    
    // Step 2: Flatten to password list
    let mut all_passwords = Vec::new();
    let mut stack = vec![tree.root];
    
    while let Some(idx) = stack.pop() {
        let node = &tree.map[idx];
        if node.node_type == NodeType::File && node.visible {
            all_passwords.push(idx);  // Store indices for path reconstruction
        }
        for &child_idx in node.children.iter().rev() {
            stack.push(child_idx);
        }
    }
    
    // Step 3: Setup TUI
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    stdout.execute(crossterm::terminal::EnterAlternateScreen)?;
    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    
    let mut query = String::new();
    let mut selected = 0;
    let mut engine = EngineBuilder::new().build();
    
    loop {
        // Step 4: Filter passwords
        let mut matches: Vec<(String, u32, usize)> = Vec::new();
        
        for &idx in &all_passwords {
            // Reconstruct path
            let mut parts = Vec::new();
            let mut node_idx = idx;
            loop {
                let n = &tree.map[node_idx];
                parts.push(n.name.clone());
                node_idx = match n.parent {
                    Some(p) => p,
                    None => break,
                };
            }
            parts.reverse();
            let path = parts.join("/");
            
            // Fuzzy match
            if let Some(score) = engine.fuzzy_match(&path, &query) {
                matches.push((path, score, idx));
            }
        }
        
        matches.sort_by(|a, b| b.1.cmp(&a.1));
        
        // Step 5: Render
        terminal.draw(|f| {
            let items: Vec<ratatui::widgets::ListItem> = matches
                .iter()
                .enumerate()
                .map(|(i, (path, _score, _))| {
                    let style = if i == selected {
                        Style::default().bg(Color::Blue)
                    } else {
                        Style::default()
                    };
                    ratatui::widgets::ListItem::new(path.clone()).style(style)
                })
                .collect();
            
            let list = ratatui::widgets::List::new(items)
                .block(ratatui::widgets::Block::default().borders(ratatui::widgets::Borders::ALL))
                .title(format!("Search: {}", query));
            
            f.render_widget(list, f.size());
        })?;
        
        // Step 6: Handle input
        if let Event::Key(key) = event::read()? {
            match key.code {
                KeyCode::Char(c) => {
                    query.push(c);
                    selected = 0;  // Reset selection when query changes
                },
                KeyCode::Backspace => {
                    query.pop();
                    selected = 0;
                },
                KeyCode::Up => selected = selected.saturating_sub(1),
                KeyCode::Down => selected = (selected + 1).min(matches.len().saturating_sub(1)),
                KeyCode::Enter => {
                    if !matches.is_empty() {
                        let selected_path = &matches[selected].0;
                        
                        // Display the password
                        crossterm::terminal::disable_raw_mode()?;
                        drop(terminal);
                        
                        let tree_cfg = TreeConfig {
                            root,
                            target: selected_path,
                            filter_type: FilterType::Disable,
                            filters: Vec::new(),
                        };
                        
                        let print_cfg = pars_core::util::tree::TreePrintConfig {
                            dir_color: None,
                            file_color: None,
                            symbol_color: None,
                            tree_color: None,
                        };
                        
                        let res = ls_io(pgp_executable, &tree_cfg, &print_cfg)?;
                        match res {
                            LsOrShow::Password(mut passwd) => {
                                use secrecy::ExposeSecret;
                                println!("{}", passwd.expose_secret());
                                passwd.zeroize();
                            },
                            LsOrShow::DirTree(t) => println!("{t}"),
                        }
                        
                        return Ok(());
                    }
                },
                KeyCode::Esc => {
                    crossterm::terminal::disable_raw_mode()?;
                    drop(terminal);
                    return Ok(());
                },
                _ => {}
            }
        }
    }
}
```

## 8. Integration with Existing CLI

### Add to parser (in cli/src/parser/sub_command.rs)
```rust
#[derive(Parser)]
pub enum SubCommands {
    #[command(about = "List passwords")]
    Ls { /* ... existing ... */ },
    
    #[command(about = "Fuzzy search passwords")]
    Search {
        #[arg(help = "Initial search query")]
        query: Option<String>,
    },
}
```

### Handle in parser (in cli/src/parser/mod.rs)
```rust
Some(SubCommands::Search { query }) => {
    let root = unwrap_root_path(cli_args.base_dir.as_deref(), &config);
    let selected = fuzzy::fuzzy_display(&root, query.as_deref())?;
    
    let tree_cfg = TreeConfig {
        root: &root,
        target: &selected,
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    
    let res = ls_io(
        &config.executable_config.pgp_executable,
        &tree_cfg,
        &Into::<TreePrintConfig>::into(&config.print_config),
    ).map_err(|e| (ParsExitCode::Error.into(), e))?;
    
    match res {
        LsOrShow::Password(mut passwd) => {
            println!("{}", passwd.expose_secret());
            passwd.zeroize();
        },
        LsOrShow::DirTree(tree) => println!("{tree}"),
    }
}
```

---

These examples show the concrete patterns used in the existing codebase and how to build the fuzzy finder!
