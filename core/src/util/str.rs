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
