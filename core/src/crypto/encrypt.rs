use std::io::Write;
use std::process::{Command, Stdio};

fn encrypt_with_key(
    executable: &str,
    public_key: &str,
    plaintext: &str,
    output_file: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut child = Command::new(executable)
        .args(&["--encrypt", "--recipient", public_key, "--output", output_file])
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
    use std::fs::write;
    use std::process::Command;

    use super::*;

    #[test]
    fn test_encrypt_with_key() {
        let public_key = "test_key.pub";
        let plaintext = "This is a test";
        let encrypted_file = "test_encrypted.gpg";

        // Generate a test key pair
        let mut gen_key_cmd = Command::new("gpg")
            .arg("--batch")
            .arg("--gen-key")
            .stdin(Stdio::piped())
            .spawn()
            .expect("Failed to start gpg process");

        {
            let stdin = gen_key_cmd.stdin.as_mut().expect("Failed to open stdin");
            stdin
                .write_all(b"Key-Type: RSA\nKey-Length: 1024\nName-Real: Test\n")
                .expect("Failed to write to stdin");
        }

        gen_key_cmd.wait().expect("Failed to wait on gpg process");

        // Test the encrypt_with_key function
        let result = encrypt_with_key("gpg", public_key, plaintext, encrypted_file);
        assert!(result.is_ok());

        // Clean up the temporary files
        std::fs::remove_file(public_key).expect("Failed to delete temporary file");
        std::fs::remove_file(encrypted_file).expect("Failed to delete temporary file");
    }
}
