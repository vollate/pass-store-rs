mod convert;
mod print;

use std::path::Path;

use bumpalo::collections::Vec as BumpVec;
use colored::Color;
use regex::Regex;

use crate::config;

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

pub struct TreePrintConfig {
    pub dir_color: Option<Color>,
    pub file_color: Option<Color>,
    pub symbol_color: Option<Color>,
    pub tree_color: Option<Color>,
}

impl<CFG: AsRef<config::PrintConfig>> From<CFG> for TreePrintConfig {
    fn from(config: CFG) -> Self {
        Self {
            dir_color: string_to_color_opt(&config.as_ref().dir_color),
            file_color: string_to_color_opt(&config.as_ref().file_color),
            symbol_color: string_to_color_opt(&config.as_ref().symbol_color),
            tree_color: string_to_color_opt(&config.as_ref().tree_color),
        }
    }
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
    pub is_recursive: bool,
    pub visible: bool,
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

pub fn string_to_color_opt(color_str: &str) -> Option<Color> {
    color_str.parse::<Color>().ok()
}
