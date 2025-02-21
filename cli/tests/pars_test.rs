#[cfg(test)]
mod tests {
    use assert_cmd::Command;
    use predicates::prelude::predicate;

    #[test]
    fn test_init() {
        let mut cmd = Command::cargo_bin("pars").unwrap();
        cmd.arg("--help")
            .env("PASS_CONFIG_PATH", "tests/test-config.toml")
            .assert()
            .success()
            .stdout(predicate::str::contains("Usage:"));
    }
}
