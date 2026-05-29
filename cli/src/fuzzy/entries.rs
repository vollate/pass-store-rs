//! Password-store entry enumeration and fuzzy filtering.

use std::fs;
use std::path::Path;

use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Matcher, Utf32Str};

/// Recursively walk the password store and collect all `.gpg` entries (relative paths,
/// `.gpg` extension stripped). Skips hidden directories and `.gpg-id` files.
pub fn collect_entries(root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    collect_entries_recursive(root, root, &mut entries);
    entries.sort();
    entries
}

fn collect_entries_recursive(root: &Path, current: &Path, entries: &mut Vec<String>) {
    let Ok(read_dir) = fs::read_dir(current) else {
        return;
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        let file_name = entry.file_name().to_string_lossy().to_string();
        if file_name.starts_with('.') {
            continue;
        }
        if path.is_dir() {
            collect_entries_recursive(root, &path, entries);
        } else if file_name.ends_with(".gpg") && file_name != ".gpg-id" {
            if let Ok(relative) = path.strip_prefix(root) {
                let rel_str = relative.to_string_lossy();
                let entry_name = rel_str.trim_end_matches(".gpg").to_string();
                entries.push(entry_name);
            }
        }
    }
}

/// Filter entries against a fuzzy query, returning (entry_name, matched_char_indices) pairs
/// sorted by relevance:
///   tier 0 = exact match (case-insensitive)
///   tier 1 = contiguous substring match (earlier position ranks higher)
///   tier 2 = fuzzy subsequence match (nucleo's score)
pub fn filter_entries(
    query: &str,
    entries: &[String],
    matcher: &mut Matcher,
) -> Vec<(String, Vec<u32>)> {
    if query.is_empty() {
        return entries.iter().map(|e| (e.clone(), Vec::new())).collect();
    }
    let pattern = Pattern::parse(query, CaseMatching::Smart, Normalization::Smart);
    let mut buf = Vec::new();
    let query_lower = query.to_lowercase();

    let mut scored: Vec<(String, Vec<u32>, u8, usize, u32)> = entries
        .iter()
        .filter_map(|entry| {
            let entry_lower = entry.to_lowercase();

            // Tier 0: exact match
            if entry_lower == query_lower {
                let indices: Vec<u32> = (0..entry.chars().count() as u32).collect();
                return Some((entry.clone(), indices, 0u8, 0usize, u32::MAX));
            }

            // Tier 1: contiguous substring match (compute indices in CHAR units, not bytes)
            if let Some(byte_pos) = entry_lower.find(&query_lower) {
                let char_start = entry_lower[..byte_pos].chars().count();
                let query_char_count = query.chars().count();
                let indices: Vec<u32> =
                    (char_start as u32..(char_start + query_char_count) as u32).collect();
                return Some((entry.clone(), indices, 1u8, char_start, u32::MAX / 2));
            }

            // Tier 2: fall back to nucleo subsequence match — get actual matched indices
            let haystack = Utf32Str::new(entry, &mut buf);
            let mut indices = Vec::new();
            let score = pattern.indices(haystack, matcher, &mut indices)?;
            indices.sort_unstable();
            indices.dedup();
            Some((entry.clone(), indices, 2u8, 0usize, score))
        })
        .collect();

    // Sort: tier ascending, then substring position ascending, then score descending
    scored.sort_by(|a, b| a.2.cmp(&b.2).then(a.3.cmp(&b.3)).then(b.4.cmp(&a.4)));

    scored.into_iter().map(|(e, idx, _, _, _)| (e, idx)).collect()
}
