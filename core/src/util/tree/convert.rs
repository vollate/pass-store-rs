use std::cell::{Ref, RefCell};
use std::collections::{HashSet, VecDeque};
use std::error::Error;
use std::fs::{canonicalize, DirEntry, FileType, ReadDir};
use std::iter::Fuse;
use std::mem;
use std::os::unix::process::parent_id;
use std::path::{self, Path, PathBuf};
use std::rc::Rc;

use bumpalo::collections::{vec, Vec as BumpVec};
use bumpalo::Bump;
use log::debug;
use regex::Regex;

use super::{DirTree, FilterType, NodeType, TreeConfig, TreeNode};
use crate::util::fs_utils::{filename_to_str, path_to_str};
use crate::{IOErr, IOErrType};

impl<'a> DirTree<'a> {
    pub fn new(config: &TreeConfig<'a>, bump: &'a Bump) -> Result<Self, Box<dyn Error>> {
        let mut tree = DirTree::build_tree(config, bump)?;
        Self::handle_whitelist(&config, &mut tree);
        Self::shrink_tree(&mut tree);
        Ok(tree)
    }

    fn handle_whitelist(config: &&TreeConfig, tree: &mut DirTree) {
        if config.filter_type == FilterType::Include {
            let mut stack: VecDeque<(usize, usize)> = VecDeque::<(usize, usize)>::new();
            stack.push_back((tree.root, 0));
            while let Some((node_idx, vec_idx)) = stack.pop_back() {
                let child_idx = {
                    let parent = &tree.map[node_idx];
                    if vec_idx >= parent.children.len() {
                        continue;
                    }
                    parent.children[vec_idx]
                };
                let child_node = &mut tree.map[child_idx];
                if !Self::filter_match(&config.filters, &child_node.name) {
                    child_node.visiable = false;
                    if !child_node.children.is_empty() {
                        stack.push_back((node_idx, vec_idx + 1));
                        stack.push_back((child_idx, 0));
                    }
                } else {
                    let mut parent_idx = node_idx;
                    loop {
                        let parent = &mut tree.map[parent_idx];
                        if parent.visiable {
                            break;
                        }
                        parent.visiable = true;
                        if parent.parent.is_none() {
                            break;
                        }
                        parent_idx = parent.parent.unwrap();
                    }
                    stack.push_back((node_idx, vec_idx + 1));
                }
            }
        }
    }

    fn shrink_tree(tree: &mut DirTree) {
        let mut queue = VecDeque::<usize>::new();
        queue.push_back(tree.root);

        while let Some(node_idx) = queue.pop_front() {
            let mut children = mem::take(&mut tree.map[node_idx].children);
            children.retain(|child_idx| {
                if tree.map[*child_idx].visiable {
                    queue.push_back(*child_idx);
                    true
                } else {
                    false
                }
            });
            tree.map[node_idx].children = children;
        }
    }

    fn build_tree<'b>(config: &'b TreeConfig<'a>, bump: &'a Bump) -> Result<Self, Box<dyn Error>> {
        let root = config.root.join(config.target);

        let mut tree = DirTree { map: BumpVec::new_in(&bump), root: 0 };
        let mut path_set = HashSet::<PathBuf>::new();

        tree.map.push(TreeNode {
            name: config.target.to_string(),
            parent: None,
            children: Vec::with_capacity(Self::count_sub_entry(&root)),
            node_type: root.as_path().into(),
            symlink_target: None, // No need to store root's symlink target
            is_rescursive: false,
            visiable: true,
        });

        path_set.insert(canonicalize(&root)?);

        let mut stack: VecDeque<(usize, Fuse<ReadDir>)> = VecDeque::<(usize, Fuse<ReadDir>)>::new();
        stack.push_back((0, root.read_dir()?.fuse()));

        while let Some((parent_idx, mut entry_iter)) = stack.pop_back() {
            if let Some(entry) = entry_iter.next() {
                let entry = entry?;
                if config.filter_type == FilterType::Exclude
                    && Self::filter_match(&config.filters, &filename_to_str(&entry.path())?)
                {
                    stack.push_back((parent_idx, entry_iter));
                    continue;
                }
                let entry_type = entry.file_type()?;
                let mut real_path = entry.path();

                while real_path.is_symlink() {
                    real_path = real_path.read_link()?;
                }
                let canonical_path = canonicalize(&real_path)?;
                let is_recursive_link = path_set.contains(&canonical_path);
                tree.map.push(TreeNode {
                    name: filename_to_str(&entry.path())?.to_string(),
                    parent: Some(parent_idx.clone()),
                    children: Vec::with_capacity(if is_recursive_link {
                        0
                    } else {
                        path_set.insert(canonical_path);
                        Self::count_sub_entry(&entry.path())
                    }),
                    node_type: entry.path().into(),
                    symlink_target: if entry_type.is_symlink() {
                        Some(path_to_str(&real_path)?.to_string())
                    } else {
                        None
                    },
                    is_rescursive: is_recursive_link,
                    visiable: true,
                });
                let child_idx = tree.map.len() - 1;
                debug!("Create tree node, Index {}: {:?}", child_idx, tree.map[child_idx]);
                tree.map[parent_idx].children.push(child_idx);

                stack.push_back((parent_idx, entry_iter));
                if entry_type.is_dir() || (entry_type.is_symlink() && real_path.is_dir()) {
                    stack.push_back((child_idx, entry.path().read_dir()?.fuse()));
                }
            }
        }
        Ok(tree)
    }
    fn count_sub_entry(path: &Path) -> usize {
        if let Ok(dir) = path.read_dir() {
            dir.count()
        } else {
            0
        }
    }

    fn filter_match(filters: &Vec<Regex>, path_str: &str) -> bool {
        for filter in filters {
            if filter.is_match(path_str) {
                return true;
            }
        }
        false
    }
}
