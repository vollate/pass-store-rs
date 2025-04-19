#[cfg(test)]
mod tests {
    use assert_cmd::Command;
    use predicates::prelude::predicate;

    #[test]
    fn cmd_init_test() {
        let mut cmd = Command::cargo_bin("pars").unwrap();
        cmd.arg("--help")
            .env("PARS_CONFIG_PATH", "tests/test-config.toml")
            .assert()
            .success()
            .stdout(predicate::str::contains("Usage:"));
    }

    #[test]
    fn cmd_insert_test() {
        let cmd = Command::cargo_bin("pars").unwrap();
        let args = ["insert", "test1/foo"];
    }

    #[test]
    fn cmd_rm_test() {}
}
