use std::collections::{HashSet, VecDeque};
use std::error::Error;
use std::fs::{self, canonicalize, DirEntry};
use std::path::{Path, PathBuf};
use std::{io, mem};

use bumpalo::collections::Vec as BumpVec;
use bumpalo::Bump;
use log::debug;
use regex::Regex;

use super::{DirTree, FilterType, TreeConfig, TreeNode};
use crate::util::fs_util::{filename_to_str, path_to_str};
use crate::util::test_util::log_test;

impl<'a> DirTree<'a> {
    pub fn new(config: &TreeConfig<'a>, bump: &'a Bump) -> Result<Self, Box<dyn Error>> {
        let mut tree = DirTree::build_tree(config, bump)?;
        Self::apply_whitelist(&config, &mut tree);
        Self::shrink_tree(&mut tree);
        Ok(tree)
    }

    fn apply_whitelist(config: &&TreeConfig, tree: &mut DirTree) {
        if config.filter_type != FilterType::Include {
            return;
        }
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
                child_node.visible = false;
                stack.push_back((node_idx, vec_idx + 1));
                if !child_node.children.is_empty() {
                    stack.push_back((child_idx, 0));
                }
            } else {
                let mut parent_idx = node_idx;
                loop {
                    let parent = &mut tree.map[parent_idx];
                    if parent.visible {
                        break;
                    }
                    parent.visible = true;
                    if parent.parent.is_none() {
                        break;
                    }
                    parent_idx = parent.parent.unwrap();
                }
                stack.push_back((node_idx, vec_idx + 1));
            }
        }
    }

    fn shrink_tree(tree: &mut DirTree) {
        let mut queue = VecDeque::<usize>::new();
        queue.push_back(tree.root);

        while let Some(node_idx) = queue.pop_front() {
            let mut children = mem::take(&mut tree.map[node_idx].children);
            children.retain(|child_idx| {
                if tree.map[*child_idx].visible {
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

        let mut tree = DirTree { map: BumpVec::new_in(bump), root: 0 };
        let mut path_set = HashSet::<PathBuf>::new();

        tree.map.push(TreeNode {
            name: config.target.to_string(),
            parent: None,
            children: Vec::with_capacity(Self::count_sub_entry(&root)),
            node_type: root.as_path().into(),
            symlink_target: None, // No need to store root's symlink target
            is_recursive: false,
            visible: true,
        });

        path_set.insert(canonicalize(&root)?);

        let mut stack = VecDeque::<(usize, Box<dyn Iterator<Item = io::Result<DirEntry>>>)>::new();
        stack.push_back((0, Box::new(Self::read_dir_sorted(&root)?)));

        while let Some((parent_idx, mut entry_iter)) = stack.pop_back() {
            if let Some(entry) = entry_iter.next() {
                let entry = entry?;
                if config.filter_type == FilterType::Exclude
                    && Self::filter_match(&config.filters, filename_to_str(&entry.path())?)
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
                let is_recursive_link =
                    path_set.contains(&canonical_path) && entry_type.is_symlink();
                tree.map.push(TreeNode {
                    name: filename_to_str(&entry.path())?.to_string(),
                    parent: Some(parent_idx),
                    children: Vec::with_capacity(if is_recursive_link {
                        0
                    } else {
                        if canonical_path.is_dir() {
                            path_set.insert(canonical_path);
                        }
                        Self::count_sub_entry(&entry.path())
                    }),
                    node_type: entry.path().into(),
                    symlink_target: if entry_type.is_symlink() {
                        Some(path_to_str(&real_path)?.to_string())
                    } else {
                        None
                    },
                    is_recursive: is_recursive_link,
                    visible: true,
                });
                let child_idx = tree.map.len() - 1;
                log_test!("Create tree node, Index {}: {:?}", child_idx, tree.map[child_idx]);
                debug!("Create tree node, Index {}: {:?}", child_idx, tree.map[child_idx]);
                tree.map[parent_idx].children.push(child_idx);

                stack.push_back((parent_idx, entry_iter));
                let need_iterate_child =
                    entry_type.is_dir() || (entry_type.is_symlink() && real_path.is_dir());
                if !is_recursive_link && need_iterate_child {
                    stack.push_back((child_idx, Box::new(Self::read_dir_sorted(entry.path())?)));
                }
            }
        }
        Ok(tree)
    }

    fn read_dir_sorted<P: AsRef<Path>>(
        path: P,
    ) -> io::Result<impl Iterator<Item = io::Result<DirEntry>>> {
        let mut entries: Vec<DirEntry> =
            fs::read_dir(path)?.collect::<Result<Vec<_>, io::Error>>()?;
        entries.sort_by_key(|e| e.file_name().to_string_lossy().into_owned());
        Ok(entries.into_iter().map(Ok).fuse())
    }

    fn count_sub_entry(path: &Path) -> usize {
        if let Ok(dir) = path.read_dir() {
            dir.count()
        } else {
            0
        }
    }

    fn filter_match(filters: &Vec<Regex>, target: &str) -> bool {
        for filter in filters {
            if filter.is_match(target) {
                return true;
            }
        }
        false
    }
}
