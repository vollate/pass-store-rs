use std::io::Write;
use std::process::{Command, Stdio};

fn encrypt_with_key(
    executable: &str,
    key_fpr: &str,
    plaintext: &str,
    output_file: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut child = Command::new(executable)
        .args(&["--encrypt", "--recipient", key_fpr, "--output", output_file])
        .stdin(Stdio::piped())
        .spawn()?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(plaintext.as_bytes())?;
    }

    let status = child.wait()?;
    if status.success() {
        println!("File encrypted successfully: {}", output_file);
        Ok(())
    } else {
        Err("GPG encryption failed".into())
    }
}

#[cfg(test)]
mod tests {
    use serial_test::serial;

    use super::super::key_management::gpg_key_gen_batch;
    use crate::util::test_utils::{clean_up_test_key, get_test_email, get_test_executable, gpg_key_gen_example_batch_input};

    #[test]
    #[serial]
    fn test_encrypt_with_key() {
        gpg_key_gen_batch(&get_test_executable(), &gpg_key_gen_example_batch_input().unwrap())
            .unwrap();
        clean_up_test_key(&get_test_executable(), &get_test_email()).unwrap();
    }
}
