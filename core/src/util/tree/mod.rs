mod convert;
mod print;

use std::path::Path;

use bumpalo::collections::Vec as BumpVec;
use colored::Color;
use regex::Regex;

#[derive(PartialEq, Eq, Clone, Copy)]
pub enum FilterType {
    Include,
    Exclude,
    Disable,
}

#[derive(Clone)]
pub struct TreeConfig<'a> {
    pub root: &'a Path,
    pub target: &'a str,
    pub filter_type: FilterType,
    pub filters: Vec<Regex>,
}

pub struct PrintConfig {
    pub dir_color: Option<Color>,
    pub file_color: Option<Color>,
    pub symbol_color: Option<Color>,
    pub tree_color: Option<Color>,
}

#[derive(Debug)]
pub enum NodeType {
    File,
    Dir,
    Symlink,
    Other,
    Invalid,
}

#[derive(Debug)]
pub struct TreeNode {
    pub name: String,
    pub parent: Option<usize>,
    pub children: Vec<usize>,
    pub node_type: NodeType,
    pub symlink_target: Option<String>,
    pub is_rescursive: bool,
    pub visiable: bool,
}

pub struct DirTree<'a> {
    pub map: BumpVec<'a, TreeNode>,
    pub root: usize,
}

impl<T: AsRef<Path>> From<T> for NodeType {
    fn from(value: T) -> Self {
        let path = value.as_ref();
        if !path.exists() {
            NodeType::Invalid
        } else if path.is_symlink() {
            NodeType::Symlink
        } else if path.is_file() {
            NodeType::File
        } else if path.is_dir() {
            NodeType::Dir
        } else {
            NodeType::Other
        }
    }
}
