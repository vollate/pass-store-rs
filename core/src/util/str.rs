use unicode_segmentation::UnicodeSegmentation;

pub fn remove_lines_postfix(src: &str, postfix: &str) -> String {
    let mut result = String::new();

    for line in src.lines() {
        if line.ends_with(postfix) {
            result.push_str(&line[..line.len() - 4]);
        } else {
            result.push_str(line);
        }
        result.push('\n');
    }
    result.pop();
    result
}

#[cfg(windows)]
pub(crate) fn fit_to_powershell(original_str: &str) -> String {
    let mut result = String::with_capacity(original_str.len());
    for g in original_str.graphemes(true) {
        match g {
            "`" => result.push_str("``"),
            "\"" => result.push_str("`\""),
            "$" => result.push_str("`$"),
            "#" => result.push_str("`#"),
            "\n" => result.push_str("`n"),
            "\r" => result.push_str("`r"),
            "\t" => result.push_str("`t"),
            "\x07" => result.push_str("`a"),
            "\x08" => result.push_str("`b"),
            "\x0C" => result.push_str("`f"),
            "\x0B" => result.push_str("`v"),
            "\x1B" => result.push_str("`e"),
            _ => result.push_str(g),
        }
    }
    result
}

#[cfg(unix)]
pub(crate) fn fit_to_unix(original_str: &str) -> String {
    let mut result = String::with_capacity(original_str.len());
    for g in original_str.graphemes(true) {
        match g {
            "\\" => result.push_str("\\\\"),
            _ => result.push_str(g),
        }
    }
    result
}
