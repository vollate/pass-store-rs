# Pass-Store-RS: Quick Reference for TUI Fuzzy Finder Development

## 📋 Quick Facts

| Aspect | Status | Details |
|--------|--------|---------|
| **Fuzzy Module** | ❌ EMPTY | `cli/src/fuzzy/mod.rs` - only a stub function |
| **TUI Framework** | ✅ AVAILABLE | `ratatui 0.29.0` - unused but imported |
| **Fuzzy Matching** | ✅ AVAILABLE | `nucleo-matcher 0.3.1` - unused but imported |
| **Tree System** | ✅ COMPLETE | `core/src/util/tree/` - fully working |
| **Password Enumeration** | ✅ READY | Via `DirTree::new()` |
| **CLI Integration** | ✅ READY | Via existing `ls` command pattern |

## 🏗️ Core Building Blocks

### 1. DirTree - Password Enumeration
```rust
// Location: core/src/util/tree/mod.rs
pub struct DirTree<'a> {
    pub map: BumpVec<'a, TreeNode>,
    pub root: usize,
}

// Usage:
let tree = DirTree::new(&tree_cfg, &bump)?;  // Builds entire tree

// Access nodes:
tree.map[idx]  // Direct index access
```

### 2. TreeConfig - Configuration
```rust
pub struct TreeConfig<'a> {
    pub root: &'a Path,           // Password store root
    pub target: &'a str,          // Subdirectory to target
    pub filter_type: FilterType,  // Include/Exclude/Disable
    pub filters: Vec<Regex>,      // Filter patterns
}

// Example: Empty config (get all)
let cfg = TreeConfig {
    root: &root_path,
    target: "",
    filter_type: FilterType::Disable,
    filters: Vec::new(),
};
```

### 3. TreeNode - Individual Entry
```rust
pub struct TreeNode {
    pub name: String,
    pub parent: Option<usize>,     // Parent node index
    pub children: Vec<usize>,      // Child node indices
    pub node_type: NodeType,       // File/Dir/Symlink
    pub visible: bool,             // Filtered visibility
}
```

### 4. Password Display - Existing
```rust
// Location: core/src/operation/ls_or_show.rs
pub fn ls_io(
    pgp_executable: &str,
    tree_cfg: &TreeConfig,
    print_cfg: &TreePrintConfig,
) -> Result<LsOrShow>

// Returns either:
// - LsOrShow::DirTree(String) for directories
// - LsOrShow::Password(SecretString) for files
```

## 🔄 Data Flow

```
Password Store (filesystem)
           ↓
    DirTree::new()  ← Build tree from root
           ↓
  DirTree (in-memory graph)
           ↓
  Flatten to Vec<String>  ← Get all password paths
           ↓
  nucleo-matcher filter  ← Fuzzy match against query
           ↓
  Vec<Match> sorted  ← Results with scores
           ↓
  ratatui UI render  ← Display interactive list
           ↓
  User selects item
           ↓
  ls_io() with selected path  ← Decrypt & display
           ↓
  Show password to user
```

## 📁 Key File Locations

### Must Reference (Read-Only)
- `core/src/util/tree/mod.rs` - Tree structures
- `core/src/util/tree/convert.rs` - Tree building logic
- `core/src/util/tree/print.rs` - Tree traversal patterns
- `core/src/operation/ls_or_show.rs` - Password listing
- `core/src/operation/find.rs` - Filter examples
- `cli/src/command/ls.rs` - CLI integration pattern

### Will Implement
- `cli/src/fuzzy/mod.rs` - Main fuzzy_display() function
- `cli/src/command/search.rs` (new) - Optional: cmd_search()
- `cli/src/parser/sub_command.rs` (modify) - Optional: add Search variant

## 🎯 Implementation Checklist

### Phase 1: Core Fuzzy Matcher
- [ ] Build DirTree from root
- [ ] Flatten tree to Vec<String> (all password paths)
- [ ] Integrate nucleo-matcher for fuzzy filtering
- [ ] Sort results by match score

### Phase 2: Basic TUI
- [ ] Initialize ratatui Terminal
- [ ] Implement input field rendering
- [ ] Implement list view rendering
- [ ] Implement status bar

### Phase 3: Interactivity
- [ ] Handle character input → update matches
- [ ] Handle arrow keys → navigate
- [ ] Handle Enter → select
- [ ] Handle Esc → cancel

### Phase 4: Polish
- [ ] Syntax highlighting for matches
- [ ] Preview pane (optional)
- [ ] Performance optimization
- [ ] Error handling

### Phase 5: Integration
- [ ] Add to SubCommands enum
- [ ] Add to parser
- [ ] Handle CLI dispatching

## 📊 Example: Get All Passwords

```rust
fn get_all_passwords(root: &Path) -> Result<Vec<String>> {
    let tree_cfg = TreeConfig {
        root,
        target: "",
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    
    let bump = Bump::new();
    let tree = DirTree::new(&tree_cfg, &bump)?;
    
    let mut passwords = Vec::new();
    let mut stack = vec![tree.root];
    
    while let Some(idx) = stack.pop() {
        let node = &tree.map[idx];
        
        if node.node_type == NodeType::File && node.visible {
            passwords.push(node.name.clone());
        }
        
        for &child_idx in node.children.iter().rev() {
            stack.push(child_idx);
        }
    }
    
    Ok(passwords)
}
```

## 📚 Useful Patterns from Existing Code

### Get DirTree from path
```rust
use core::util::tree::{DirTree, TreeConfig, FilterType};
use bumpalo::Bump;

let cfg = TreeConfig {
    root: &root_path,
    target: "",
    filter_type: FilterType::Disable,
    filters: vec![],
};

let bump = Bump::new();
let tree = DirTree::new(&cfg, &bump)?;
```

### Filter using TreeConfig (existing pattern)
```rust
// From: core/src/operation/find.rs
let mut cfg = tree_cfg.clone();
cfg.filter_type = FilterType::Include;
cfg.filters = vec![Regex::new("pattern")?];

let tree = DirTree::new(&cfg, &bump)?;
```

### Display password (existing pattern)
```rust
// From: cli/src/command/ls.rs
let tree_cfg = TreeConfig {
    root: &root,
    target: "path/to/password",  // Selected path
    filter_type: FilterType::Disable,
    filters: Vec::new(),
};

let res = ls_io(&pgp_executable, &tree_cfg, &print_cfg)?;

match res {
    LsOrShow::Password(mut passwd) => {
        println!("{}", passwd.expose_secret());
        passwd.zeroize();
    },
    LsOrShow::DirTree(tree) => println!("{tree}"),
}
```

## 🔧 Function Signature for fuzzy_display()

### Option A: Minimal
```rust
pub fn fuzzy_display(root: &Path) -> Result<String> {
    // Returns selected password path
    // Or error if cancelled
}
```

### Option B: With initial query
```rust
pub fn fuzzy_display(root: &Path, query: Option<&str>) -> Result<String> {
    // Pre-populate search with query
    // Return selected path
}
```

### Option C: With config
```rust
pub struct FuzzyConfig {
    pub initial_query: Option<String>,
    pub preview_pane: bool,
}

pub fn fuzzy_display(root: &Path, config: FuzzyConfig) -> Result<String>
```

## ⚠️ Important Notes

1. **Tree is Read-Only**: DirTree uses arena allocation (Bumpalo). Don't try to modify.
2. **Indices are Stable**: Index-based access is safe throughout tree lifetime.
3. **GPG Keys Needed**: To decrypt, need access to GPG keys (already handled by core).
4. **Symlinks Handled**: Tree already detects and prevents recursive symlinks.
5. **`.gpg` Extension**: Passwords are stored as `.gpg` files, but tree/display strips this.

## 🚀 Next Steps

1. **Read the full infrastructure analysis:** `INFRASTRUCTURE_ANALYSIS.md`
2. **Review architecture:** `ARCHITECTURE_DIAGRAM.md`
3. **Check existing tree tests:** `core/src/util/tree/print.rs` (test section)
4. **Review ls command:** `cli/src/command/ls.rs`
5. **Start implementing:** `cli/src/fuzzy/mod.rs`

---

**Total lines of working infrastructure: ~3000 LOC**
**Amount left to implement: ~500-1000 LOC** (TUI + fuzzy matching)
**Estimated effort: 2-4 hours for basic version, 4-8 hours for polished version**
